import SwiftUI
import WebContent

struct HTMLReaderScreen: View {
    let source: WebPageSource
    @StateObject private var state = WebPageState()
    @StateObject private var interaction = AIInteraction()
    @EnvironmentObject private var ai: AIWorkspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebPageView(source:source,state:state,actions:ai.settings.actions,onAction:{interaction.begin($0,workspace:ai)})
                .navigationTitle(state.title.isEmpty ? source.title : state.title)
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
                .alert("无法打开网页", isPresented: Binding(get: { state.issue != nil }, set: { if !$0 { state.issue = nil } })) {
                    Button("复制诊断") { UIPasteboard.general.string = state.issue }
                    Button("知道了") { state.issue = nil }
                } message: { Text(state.issue ?? "") }
        }
        .modifier(AIHost(interaction: interaction))
    }
}
