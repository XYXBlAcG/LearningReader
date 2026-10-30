import SwiftUI
import WebKit
import LearningCore

struct MarkdownContentView: UIViewRepresentable {
    let markdown: String
    var followsOutput=false
    var initialPosition:Double=0
    var onPosition:((Double)->Void)?
    var onIssue:(String?)->Void = {_ in }
    func makeCoordinator() -> Coordinator { Coordinator(followsOutput:followsOutput,initialPosition:initialPosition,onPosition:onPosition) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator,name:"studyPosition")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        context.coordinator.onIssue = onIssue
        web.isOpaque = true
        web.backgroundColor = .white
        web.scrollView.backgroundColor = .white
        web.scrollView.contentInsetAdjustmentBehavior = .never
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
    static func dismantleUIView(_ web:WKWebView,coordinator:Coordinator) {
        web.callAsyncJavaScript("return window.scrollY",arguments:[:],in:nil,in:.page){result in if case .success(let raw)=result,let value=raw as? Double {coordinator.onPosition?(value)} }
        web.stopLoading();web.navigationDelegate=nil
        web.configuration.userContentController.removeScriptMessageHandler(forName:"studyPosition")
    }
    final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandler {
        let followsOutput:Bool
        let initialPosition:Double
        let onPosition:((Double)->Void)?
        init(followsOutput:Bool,initialPosition:Double,onPosition:((Double)->Void)?) {self.followsOutput=followsOutput;self.initialPosition=initialPosition;self.onPosition=onPosition}
        func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
            guard message.frameInfo.isMainFrame,message.frameInfo.request.url?.lastPathComponent=="ai-answer.html",let value=message.body as? Double else {return}
            onPosition?(value)
        }
        var markdown = ""
        var ready = false
        var onIssue: ((String?) -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(webView) }
        func render(_ web: WKWebView) {
            web.callAsyncJavaScript("await window.AIAnswer.update(source,follow,position)", arguments: ["source":markdown,"follow":followsOutput,"position":initialPosition], in: nil, in: .page) { [weak self] result in
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
