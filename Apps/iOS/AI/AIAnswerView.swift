import SwiftUI
import WebKit
import LearningCore

struct AIAnswerView: UIViewRepresentable {
    let markdown: String
    let onIssue: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        context.coordinator.onIssue = onIssue
        web.isOpaque = false; web.backgroundColor = .white
        context.coordinator.markdown = markdown
        web.loadFileURL(ReaderAssets.reader.appendingPathComponent("ai-answer.html"), allowingReadAccessTo: ReaderAssets.reader)
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onIssue = onIssue
        guard context.coordinator.markdown != markdown else { return }
        context.coordinator.markdown = markdown
        if context.coordinator.ready { context.coordinator.render(web) }
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { web.stopLoading(); web.navigationDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var markdown = ""
        var ready = false
        var onIssue: ((String?) -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(webView) }
        func render(_ web: WKWebView) {
            web.callAsyncJavaScript("await window.AIAnswer.update(source)", arguments: ["source": markdown], in: nil, in: .page) { [weak self] result in
                switch result {
                case .success: self?.onIssue?(nil)
                case .failure(let error): self?.onIssue?("回答排版失败：" + error.localizedDescription)
                }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onIssue?("无法载入回答页面：" + error.localizedDescription) }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if navigationAction.navigationType == .linkActivated {
                if ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(url.isFileURL ? .allow : .cancel) }
        }
    }
}
