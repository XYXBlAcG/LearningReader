import SwiftUI
import UniformTypeIdentifiers

struct WebWorkspaceHost: ViewModifier {
    @ObservedObject var model: WebWorkspaceModel
    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: Binding(get: { model.picker != nil }, set: { if !$0 { model.picker = nil } }), allowedContentTypes: model.picker == .folder ? [.folder] : [.html]) { result in
                switch result {
                case .success(let url): model.importFile(url)
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { model.issue = "选择 HTML 文件\n" + error.localizedDescription }
                }
            }
            .fullScreenCover(item: $model.presentation, onDismiss: model.discardPending) { _ in WebWorkspacePresentation(model: model) }
            .alert("网页", isPresented: Binding(get: { model.issue != nil && model.presentation == nil }, set: { if !$0 { model.issue = nil } })) {
                Button("复制诊断") { UIPasteboard.general.string = model.issue }
                Button("知道了") { model.issue = nil }
            } message: { Text(model.issue ?? "") }
            .onDisappear { if model.presentation == nil { model.stop() } }
    }
}

struct WebWorkspacePresentation: View {
    @ObservedObject var model: WebWorkspaceModel
    var body: some View {
        Group {
            switch model.presentation {
            case .choose(let draft):
                NavigationStack {
                    List(draft.entries, id: \.self) { entry in Button(entry) { model.choose(entry) } }
                        .navigationTitle("选择网页")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { model.presentation = nil } } }
                }
            case .local(let source): HTMLReaderScreen(source: source)
            case .address:
                WebAddressScreen(initial: "", onOpen: { model.presentation = .browser($0) }, onCancel: { model.presentation = nil })
            case .browser(let url): WebBrowserScreen(initialURL: url)
            case nil: EmptyView()
            }
        }
        .alert("网页", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) {
            Button("复制诊断") { UIPasteboard.general.string = model.issue }
            Button("知道了") { model.issue = nil }
        } message: { Text(model.issue ?? "") }
    }
}
