import SwiftUI
import WebKit
import LearningCore

struct ReaderGraphView:View {
    let snapshot:CourseSnapshot
    let kind:String
    let path:String
    let onOpen:(ReaderDocumentTarget)->Void
    @State private var issue:String?
    @State private var global=false
    @State private var loading=true
    @State private var reload=0
    var body:some View {
        VStack(spacing:16) {
            Picker("关联范围",selection:$global){Text("本页关联").tag(false);Text("全部知识").tag(true)}.pickerStyle(.segmented).padding(.horizontal).padding(.top,8)
            if let issue {VStack{Text(issue).foregroundStyle(.secondary);Button("重试"){self.issue=nil;loading=true;reload+=1}}.padding()}
            GraphSurface(snapshot:snapshot,kind:kind,path:path,global:global,onOpen:onOpen,onIssue:{issue=$0},onLoading:{loading=$0;if $0 {issue=nil}}).id(reload)
                .overlay{if loading {ProgressView("加载中…").padding(20).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))}}
        }
    }
}

private struct GraphSurface:UIViewRepresentable {
    let snapshot:CourseSnapshot
    let kind:String
    let path:String
    let global:Bool
    let onOpen:(ReaderDocumentTarget)->Void
    let onIssue:(String)->Void
    let onLoading:(Bool)->Void
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
        let changed=context.coordinator.host.kind != kind || context.coordinator.host.path != path || context.coordinator.host.global != global
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
        var generation=0
        var cachedGraph:Any?
        init(_ host:GraphSurface) { self.host=host }
        func webView(_ web:WKWebView,didFinish navigation:WKNavigation!) { ready=true;update(web) }
        func update(_ web:WKWebView) {
            generation+=1
            let request=generation
            Task {@MainActor [weak self,weak web] in
                guard let self,let web,self.generation==request else {return}
                self.host.onLoading(true)
                await Task.yield()
                guard self.generation==request else {return}
            do {
                guard let data=host.snapshot.course.indices["graph.json"] else { throw ReaderError.invalidIndex }
                if cachedGraph==nil {cachedGraph=try JSONSerialization.jsonObject(with:data)}
                guard let graph=cachedGraph else {throw ReaderError.invalidIndex}
                web.callAsyncJavaScript("await window.NativeGraph.update(graph,kind,path,global)",arguments:["graph":graph,"kind":host.kind,"path":host.path,"global":host.global],in:nil,in:.page) { [weak self] result in
                    guard let self,self.generation==request else {return}
                    self.host.onLoading(false)
                    if case .failure(let error)=result {self.host.onIssue(error.localizedDescription)}
                }
            } catch {host.onLoading(false);host.onIssue(error.localizedDescription)}
            }
        }
        func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.standardizedFileURL == ReaderAssets.reader.appendingPathComponent("graph-panel.html").standardizedFileURL,
                  let data=try? JSONSerialization.data(withJSONObject:message.body),
                  let target=try? JSONDecoder().decode(ReaderDocumentTarget.self,from:data),
                  host.snapshot.course.documents.contains(where:{$0.kind==target.kind && $0.path==target.path}) else { return }
            host.onOpen(target)
        }
        func webView(_ web:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {host.onLoading(false);host.onIssue(error.localizedDescription)}
        func webView(_ web:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {host.onLoading(false);host.onIssue(error.localizedDescription)}
    }
}
