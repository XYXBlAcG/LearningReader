import SwiftUI
import WebKit
import WebContent
import AICore

@MainActor
final class WebPageState: ObservableObject {
    @Published var canBack = false
    @Published var canForward = false
    @Published var loading = false
    @Published var title = ""
    @Published var issue: String?
    weak var webView: WKWebView?
}

struct WebPageView: UIViewControllerRepresentable {
    let source: WebPageSource
    let state: WebPageState
    var onExplain: ((AIMaterial) -> Void)? = nil
    func makeUIViewController(context: Context) -> WebPageController { WebPageController(source: source, state: state, onExplain: onExplain) }
    func updateUIViewController(_ controller: WebPageController, context: Context) { controller.update(source: source, onExplain: onExplain) }
    static func dismantleUIViewController(_ controller: WebPageController, coordinator: ()) { controller.close() }
}

@MainActor
final class WebPageController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var source: WebPageSource
    private let state: WebPageState
    private var web: ExplainingWebView!
    private var onExplain: ((AIMaterial) -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var cancelDialog: (() -> Void)?

    init(source: WebPageSource, state: WebPageState, onExplain: ((AIMaterial) -> Void)?) {
        self.source = source
        self.state = state
        self.onExplain = onExplain
        super.init(nibName: nil, bundle: nil)
    }

    func update(source: WebPageSource, onExplain: ((AIMaterial) -> Void)?) {
        self.onExplain = onExplain
        web?.onExplain = onExplain
        guard self.source != source else { return }
        self.source = source
        if isViewLoaded { loadSource() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: source.storageID)
        web = ExplainingWebView(frame: .zero, configuration: configuration)
        web.onExplain = onExplain
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        view = web
        state.webView = web
        observations = [
            web.observe(\.canGoBack, options: [.new]) { [weak self] web, _ in self?.state.canBack = web.canGoBack },
            web.observe(\.canGoForward, options: [.new]) { [weak self] web, _ in self?.state.canForward = web.canGoForward },
            web.observe(\.isLoading, options: [.new]) { [weak self] web, _ in self?.state.loading = web.isLoading },
            web.observe(\.title, options: [.new]) { [weak self] web, _ in self?.state.title = web.title ?? "" }
        ]
        loadSource()
    }

    func close() {
        cancelDialog?()
        cancelDialog = nil
        observations.removeAll()
        web?.stopLoading()
        web?.navigationDelegate = nil
        web?.uiDelegate = nil
        if state.webView === web { state.webView = nil }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        switch source.navigation(to: url) {
        case .allow: decisionHandler(.allow)
        case .external:
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        case .reject:
            state.issue = "无法打开此链接：" + url.absoluteString
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { state.issue = nil }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let failure = error as NSError
        guard failure.code != NSURLErrorCancelled else { return }
        let failedURL = failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? source.url
        state.issue = "网页加载失败\n" + failure.localizedDescription + "\n" + failure.domain + " (" + String(failure.code) + ")\n" + failedURL.absoluteString
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard cancelDialog == nil, viewIfLoaded?.window != nil else { completionHandler(); return }
        let alert = UIAlertController(title: source.title, message: message, preferredStyle: .alert)
        cancelDialog = completionHandler
        alert.addAction(UIAlertAction(title: "好", style: .default) { [weak self] _ in self?.completeDialog(completionHandler) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard cancelDialog == nil, viewIfLoaded?.window != nil else { completionHandler(false); return }
        let alert = UIAlertController(title: source.title, message: message, preferredStyle: .alert)
        cancelDialog = { completionHandler(false) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.completeDialog { completionHandler(false) } })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in self?.completeDialog { completionHandler(true) } })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard cancelDialog == nil, viewIfLoaded?.window != nil else { completionHandler(nil); return }
        let alert = UIAlertController(title: source.title, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        cancelDialog = { completionHandler(nil) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.completeDialog { completionHandler(nil) } })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in self?.completeDialog { completionHandler(alert?.textFields?.first?.text) } })
        present(alert, animated: true)
    }

    private func loadSource() {
        state.issue = nil
        state.title = ""
        switch source {
        case .local(_, let file, let root): web.loadFileURL(file, allowingReadAccessTo: root.standardizedFileURL.resolvingSymlinksInPath())
        case .website(let url): web.load(URLRequest(url: url))
        }
    }

    private func completeDialog(_ completion: () -> Void) {
        guard cancelDialog != nil else { return }
        cancelDialog = nil
        completion()
    }
}
