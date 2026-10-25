import SwiftUI
import WebKit
import LearningCore

struct ReaderGraphView:View {
    let snapshot:CourseSnapshot
    let kind:String
    let path:String
    let onOpen:(ReaderDocumentTarget)->Void
    @State private var issue:String?
    var body:some View {
        VStack {
            if let issue { Text(issue).foregroundStyle(.secondary).padding() }
            GraphSurface(snapshot:snapshot,kind:kind,path:path,onOpen:onOpen,onIssue:{issue=$0})
        }
    }
}

private struct GraphSurface:UIViewRepresentable {
    let snapshot:CourseSnapshot
    let kind:String
    let path:String
    let onOpen:(ReaderDocumentTarget)->Void
    let onIssue:(String)->Void
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeUIView(context:Context)->WKWebView {
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator,name:"graphNavigate")
        let web=WKWebView(frame:.zero,configuration:config)
        web.navigationDelegate=context.coordinator
        web.loadFileURL(ReaderAssets.reader.appendingPathComponent("graph-panel.html"),allowingReadAccessTo:ReaderAssets.reader)
        return web
    }
    func updateUIView(_ web:WKWebView,context:Context) {
        let changed=context.coordinator.host.kind != kind || context.coordinator.host.path != path
        context.coordinator.host=self
        if changed && context.coordinator.ready { context.coordinator.update(web) }
    }
    static func dismantleUIView(_ web:WKWebView,coordinator:Coordinator) {
        web.stopLoading();web.navigationDelegate=nil
        web.configuration.userContentController.removeScriptMessageHandler(forName:"graphNavigate")
    }
    final class Coordinator:NSObject,WKNavigationDelegate,WKScriptMessageHandler {
        var host:GraphSurface
        var ready=false
        init(_ host:GraphSurface) { self.host=host }
        func webView(_ web:WKWebView,didFinish navigation:WKNavigation!) { ready=true;update(web) }
        func update(_ web:WKWebView) {
            do {
                guard let data=host.snapshot.course.indices["graph.json"] else { throw ReaderError.invalidIndex }
                let graph=try JSONSerialization.jsonObject(with:data)
                web.callAsyncJavaScript("window.NativeGraph.update(graph,kind,path)",arguments:["graph":graph,"kind":host.kind,"path":host.path],in:nil,in:.page) { [weak self] result in
                    if case .failure(let error)=result { self?.host.onIssue(error.localizedDescription) }
                }
            } catch { host.onIssue(error.localizedDescription) }
        }
        func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.standardizedFileURL == ReaderAssets.reader.appendingPathComponent("graph-panel.html").standardizedFileURL,
                  let data=try? JSONSerialization.data(withJSONObject:message.body),
                  let target=try? JSONDecoder().decode(ReaderDocumentTarget.self,from:data),
                  host.snapshot.course.documents.contains(where:{$0.kind==target.kind && $0.path==target.path}) else { return }
            host.onOpen(target)
        }
        func webView(_ web:WKWebView,didFail navigation:WKNavigation!,withError error:Error) { host.onIssue(error.localizedDescription) }
        func webView(_ web:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { host.onIssue(error.localizedDescription) }
    }
}
