import WebKit
import AICore

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
                guard let material = await snapshot.value, let self, self.url == identity else { return }
                self.onExplain?(material)
            }
        }
        Task { if await snapshot.value == nil { action.attributes = .disabled } }
        builder.insertChild(UIMenu(options: .displayInline, children: [action]), atStartOfMenu: .root)
    }

    private func selectedMaterial() async -> AIMaterial? {
        let course = courseSelection
        let script = course ? #"""
        const article = document.getElementById('article');
        const text = article && window.ReaderSelectionCopy?.selectionMarkdown(article);
        const selection = document.getSelection();
        const anchor = selection?.anchorNode;
        const element = anchor?.nodeType === 1 ? anchor : anchor?.parentElement;
        const block = element?.closest('p,li,blockquote');
        const context = block ? [block.previousElementSibling, block, block.nextElementSibling].filter(Boolean).map(node => ReaderSelectionCopy.elementMarkdown(node)).join('\n\n').slice(0,6000) : '';
        return {text: text || '', title: document.getElementById('crumb')?.textContent || document.title, context};
        """# : #"""
        return {text: document.getSelection()?.toString() || '', title: document.title, context: ''};
        """#
        let identity = url
        guard let raw = try? await callAsyncJavaScript(script, arguments: [:], in: nil, in: course ? .page : .defaultClient),
              url == identity, let data = raw as? [String: String], let text = data["text"], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AIMaterial(title: data["title"] ?? "阅读内容", text: text, context: data["context"] ?? "")
    }
}
