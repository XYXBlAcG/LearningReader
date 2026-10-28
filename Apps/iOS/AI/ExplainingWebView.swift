import WebKit
import AICore
import LearningCore

@MainActor
struct AISelectionCommand {
    let action: AISelectionAction
    let load: @MainActor () async throws -> AIMaterial
}

@MainActor
final class ExplainingWebView: WKWebView {
    var onAction: ((AISelectionCommand) -> Void)?
    var actions: [AISelectionAction] = [.explain]
    var courseSelection = false
    private var bootstrapIssue: String?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame:frame,configuration:configuration)
        do {
            let source=try String(contentsOf:ReaderAssets.reader.appendingPathComponent("explanation.js"),encoding:.utf8)
            configuration.userContentController.addUserScript(WKUserScript(source:source+"\nwindow.ReaderPageSelection=ReaderExplanation.bindWebpage(document);",injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:.defaultClient))
        } catch { bootstrapIssue=error.localizedDescription }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with:builder)
        guard builder.system == .context, onAction != nil else { return }
        let world: WKContentWorld = courseSelection ? .page : .defaultClient
        let prepare = courseSelection ? "window.MathReaderBridge?.prepareSelection()" : "window.ReaderPageSelection?.material(); undefined"
        callAsyncJavaScript(prepare,arguments:[:],in:nil,in:world,completionHandler:nil)
        let expectedURL=url
        let items=actions.filter(\.enabled).map { action in
            UIAction(title:action.title,image:UIImage(systemName:"sparkles")) { [weak self] _ in
                guard let self else { return }
                let command=AISelectionCommand(action:action,load:{ [weak self] in
                    guard let self else { throw AISelectionError.documentChanged }
                    return try await self.selectedMaterial(expectedURL:expectedURL)
                })
                self.onAction?(command)
            }
        }
        if !items.isEmpty { builder.insertChild(UIMenu(options:.displayInline,children:items),atStartOfMenu:.root) }
    }

    private func selectedMaterial(expectedURL:URL?) async throws -> AIMaterial {
        guard window != nil, url == expectedURL else { throw AISelectionError.documentChanged }
        if let bootstrapIssue, !courseSelection { throw AIError.generation("加载选区脚本："+bootstrapIssue) }
        let script = courseSelection
            ? "if(!window.MathReaderBridge) throw new Error('阅读器桥接未就绪'); return await window.MathReaderBridge.prepareMaterial(window.MathReaderBridge.material())"
            : "if(!window.ReaderPageSelection) throw new Error('选区脚本未就绪'); return window.ReaderPageSelection.material()"
        let world:WKContentWorld=courseSelection ? .page : .defaultClient
        let raw=try await readerJavaScript(script,world:world)
        try Task.checkCancellation()
        guard let raw, !(raw is NSNull) else { throw AISelectionError.noSelection }
        guard let data=raw as? [String:String], let documentID=data["identity"], let document=data["document"], let text=data["text"], !text.isEmpty else { throw AISelectionError.invalidPayload }
        let check = courseSelection ? "return window.MathReaderBridge?.identity() || ''" : "return document.location.href"
        let identity=try await readerJavaScript(check,world:world)
        guard window != nil, url == expectedURL, identity as? String == documentID else { throw AISelectionError.documentChanged }
        let source=StudySource(courseID:data["courseID"] ?? "",kind:data["kind"] ?? "web",path:data["path"] ?? expectedURL?.absoluteString ?? "",anchor:data["anchor"] ?? "",fingerprint:StudySource.hash(document))
        return AIMaterial(title:data["title"] ?? "阅读内容",text:text,document:document,question:data["question"],source:source)
    }
}
