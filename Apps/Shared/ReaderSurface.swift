import SwiftUI
import WebKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
typealias PlatformReaderView = NSViewRepresentable
#else
import UIKit
typealias PlatformReaderView = UIViewRepresentable
#endif
import LearningCore

@MainActor
final class ReaderController: ObservableObject {
    @Published var state: ReaderWebState?
    weak var webView: WKWebView?

    func send(_ command: String, payload: [String: String] = [:]) {
        webView?.callAsyncJavaScript("window.MathReaderBridge?.dispatch(command, payload)", arguments: ["command": command, "payload": payload], in: nil, in: .page, completionHandler: nil)
    }

    func search() {
        if state?.sidebar != true { send("sidebar") }
        webView?.evaluateJavaScript("document.getElementById('searchInput').focus()")
    }
}

struct ReaderSurface: PlatformReaderView {
    let snapshot: CourseSnapshot
    let sourceID: String
    let legacy: Bool
    @ObservedObject var controller: ReaderController
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(snapshot: snapshot, controller: controller, onError: onError) }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) { }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { dismantle(view) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) { }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { dismantle(view) }
    #endif

    func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "mathreader")
        configuration.userContentController.add(context.coordinator, name: "mathReader")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "readerResource")
        if let source = try? ReaderAssets.nativeFetch {
            configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let identity = "window.READER_SOURCE_ID=" + String(decoding: try! JSONEncoder().encode(sourceID), as: UTF8.self) + ";window.READER_LEGACY=" + (legacy ? "true" : "false") + ";"
        configuration.userContentController.addUserScript(WKUserScript(source: identity, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        #if os(iOS)
        web.isOpaque = false
        web.backgroundColor = .white
        web.scrollView.backgroundColor = .white
        web.scrollView.contentInsetAdjustmentBehavior = .never
        #endif
        web.allowsBackForwardNavigationGestures = false
        controller.webView = web
        web.load(URLRequest(url: URL(string: "mathreader://local/reader/index.html")!))
        return web
    }

    static func dismantle(_ view: WKWebView) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "mathReader")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "readerResource", contentWorld: .page)
    }

    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
        let snapshot: CourseSnapshot
        let controller: ReaderController
        let onError: (String) -> Void

        init(snapshot: CourseSnapshot, controller: ReaderController, onError: @escaping (String) -> Void) {
            self.snapshot = snapshot
            self.controller = controller
            self.onError = onError
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            do {
                guard let url = urlSchemeTask.request.url, url.host == "local" else { throw ReaderError.invalidPath }
                let file = try snapshot.resource(path: URLComponents(url: url, resolvingAgainstBaseURL: false)!.percentEncodedPath)
                let data = try Data(contentsOf: file)
                let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime, "Access-Control-Allow-Origin": "*", "Content-Length": String(data.count)])!
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch { urlSchemeTask.didFailWithError(error) }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) { }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            do {
                guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "mathreader", message.frameInfo.request.url?.host == "local",
                      let body = message.body as? [String: String], let raw = body["url"], let url = URL(string: raw),
                      url.scheme == "mathreader", url.host == "local" else { throw ReaderError.invalidPath }
                let file = try snapshot.resource(path: URLComponents(url: url, resolvingAgainstBaseURL: false)!.percentEncodedPath)
                let data = try Data(contentsOf: file)
                let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                replyHandler(["status": 200, "mime": mime, "body": data.base64EncodedString()], nil)
            } catch {
                replyHandler(["status": 404, "mime": "text/plain", "body": ""], nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "mathreader",
                  message.frameInfo.request.url?.host == "local", message.frameInfo.request.url?.path == "/reader/index.html",
                  let body = message.body as? [String: Any], body["type"] as? String == "state",
                  let raw = body["state"], let data = try? JSONSerialization.data(withJSONObject: raw),
                  let state = try? JSONDecoder().decode(ReaderWebState.self, from: data) else { return }
            controller.state = state
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.MathReaderBridge?.connect()")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "mathreader", url.host == "local" { decisionHandler(.allow); return }
            if ["https", "http"].contains(url.scheme ?? ""), navigationAction.targetFrame?.isMainFrame != false {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            }
            decisionHandler(.cancel)
        }
    }
}
