import SwiftUI
import WebKit
import LocalHTML

@MainActor
final class HTMLReaderState: ObservableObject {
    @Published var canBack = false
    @Published var canForward = false
    @Published var loading = false
    @Published var title = ""
    @Published var issue: String?
    weak var webView: WKWebView?
}

struct HTMLReaderScreen: View {
    let document: HTMLDocument
    let file: URL
    let root: URL
    @StateObject private var state = HTMLReaderState()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HTMLWebView(document: document, file: file, root: root, state: state)
                .navigationTitle(state.title.isEmpty ? document.name : state.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { state.webView?.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!state.canBack).accessibilityLabel("后退")
                        Button { state.webView?.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!state.canForward).accessibilityLabel("前进")
                        Spacer()
                        if state.loading { ProgressView() }
                        Button { state.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("重新加载")
                    }
                }
                .alert("无法打开网页", isPresented: Binding(get: { state.issue != nil }, set: { if !$0 { state.issue = nil } })) { Button("知道了") { state.issue = nil } } message: { Text(state.issue ?? "") }
        }
    }
}

struct HTMLWebView: UIViewControllerRepresentable {
    let document: HTMLDocument
    let file: URL
    let root: URL
    let state: HTMLReaderState

    func makeUIViewController(context: Context) -> HTMLWebController {
        HTMLWebController(document: document, file: file, root: root, state: state)
    }
    func updateUIViewController(_ controller: HTMLWebController, context: Context) { }
    static func dismantleUIViewController(_ controller: HTMLWebController, coordinator: ()) { controller.close() }
}

@MainActor
final class HTMLWebController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let document: HTMLDocument
    private let file: URL
    private let root: URL
    private let state: HTMLReaderState
    private var web: WKWebView!
    private var observations: [NSKeyValueObservation] = []
    private var cancelDialog: (() -> Void)?

    init(document: HTMLDocument, file: URL, root: URL, state: HTMLReaderState) {
        self.document = document
        self.file = file
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: document.id)
        web = WKWebView(frame: .zero, configuration: configuration)
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
        web.loadFileURL(file, allowingReadAccessTo: root)
    }

    func close() {
        cancelDialog?()
        cancelDialog = nil
        observations.removeAll()
        web?.stopLoading()
        web?.navigationDelegate = nil
        web?.uiDelegate = nil
        state.webView = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL {
            let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            decisionHandler(components.starts(with: root.pathComponents) ? .allow : .cancel)
        } else if ["about", "data", "blob"].contains(url.scheme ?? "") {
            decisionHandler(.allow)
        } else if ["http", "https", "mailto", "tel"].contains(url.scheme ?? ""), navigationAction.targetFrame?.isMainFrame != false {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        } else if navigationAction.targetFrame?.isMainFrame == false, ["http", "https"].contains(url.scheme ?? "") {
            decisionHandler(.allow)
        } else { decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { state.issue = error.localizedDescription }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard cancelDialog == nil, viewIfLoaded?.window != nil else { completionHandler(); return }
        let alert = UIAlertController(title: document.name, message: message, preferredStyle: .alert)
        cancelDialog = completionHandler
        alert.addAction(UIAlertAction(title: "好", style: .default) { [weak self] _ in self?.completeDialog(completionHandler) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard cancelDialog == nil, viewIfLoaded?.window != nil else { completionHandler(false); return }
        let alert = UIAlertController(title: document.name, message: message, preferredStyle: .alert)
        cancelDialog = { completionHandler(false) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.completeDialog { completionHandler(false) } })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in self?.completeDialog { completionHandler(true) } })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard cancelDialog == nil, viewIfLoaded?.window != nil else { completionHandler(nil); return }
        let alert = UIAlertController(title: document.name, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        cancelDialog = { completionHandler(nil) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.completeDialog { completionHandler(nil) } })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in self?.completeDialog { completionHandler(alert?.textFields?.first?.text) } })
        present(alert, animated: true)
    }

    private func completeDialog(_ completion: () -> Void) {
        guard cancelDialog != nil else { return }
        cancelDialog = nil
        completion()
    }
}
