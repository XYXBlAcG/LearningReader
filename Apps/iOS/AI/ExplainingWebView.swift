import WebKit
import AICore
import LearningCore

@MainActor
final class ExplainingWebView: WKWebView {
    var onExplain: ((AIMaterial) -> Void)?
    var courseSelection = false

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, onExplain != nil else { return }
        let identity = url
        let snapshot = Task { [weak self] in await self?.selectedMaterial() }
        let action = UIAction(title: "讲一讲", image: UIImage(systemName: "sparkles")) { [weak self] _ in
            Task { [weak self] in
                guard let captured = await snapshot.value, let self, self.window != nil, self.url == identity else { return }
                let script = self.courseSelection ? "return window.MathReaderBridge?.identity() || ''" : "return document.location.href"
                guard let current = try? await self.callAsyncJavaScript(script, arguments: [:], in: nil, in: self.courseSelection ? .page : .defaultClient),
                      current as? String == captured.identity, self.window != nil, self.url == identity else { return }
                self.onExplain?(captured.material)
            }
        }
        Task { if await snapshot.value == nil { action.attributes = .disabled } }
        builder.insertChild(UIMenu(options: .displayInline, children: [action]), atStartOfMenu: .root)
    }

    private struct CapturedMaterial {
        let identity: String
        let material: AIMaterial
    }

    private func selectedMaterial() async -> CapturedMaterial? {
        let course = courseSelection
        let script: String
        if course { script = "return window.MathReaderBridge?.material()" }
        else {
            guard let extraction = try? String(contentsOf: ReaderAssets.reader.appendingPathComponent("explanation.js"), encoding: .utf8) else { return nil }
            script = extraction + "\nreturn window.ReaderExplanation.webpage(document)"
        }
        let identity = url
        guard let raw = try? await callAsyncJavaScript(script, arguments: [:], in: nil, in: course ? .page : .defaultClient),
              url == identity, let data = raw as? [String: String], let documentID = data["identity"], let document = data["document"],
              let text = data["text"], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return CapturedMaterial(identity: documentID, material: AIMaterial(title: data["title"] ?? "阅读内容", text: text, document: document))
    }
}
