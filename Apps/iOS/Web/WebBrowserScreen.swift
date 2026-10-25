import SwiftUI
import WebContent

struct WebBrowserScreen: View {
    @State private var address: URL
    @StateObject private var state = WebPageState()
    @StateObject private var interaction = AIInteraction()
    @EnvironmentObject private var ai: AIWorkspace
    @State private var editingAddress = false
    @Environment(\.dismiss) private var dismiss

    init(initialURL: URL) { _address = State(initialValue: initialURL) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WebPageView(source:.website(address),state:state,actions:ai.settings.actions,onAction:{interaction.begin($0,workspace:ai)}).ignoresSafeArea()
            if let issue = state.issue {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(issue).font(.callout).textSelection(.enabled)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
            Menu {
                Button("输入网址", systemImage: "link") { editingAddress = true }
                Button("退出", systemImage: "xmark") { dismiss() }
            } label: {
                ZStack {
                    if state.loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)) }
                }
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
            }
            .accessibilityLabel("网页菜单")
            .padding(12)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .modifier(AIHost(interaction: interaction))
        .sheet(isPresented: $editingAddress) {
            WebAddressScreen(initial: state.webView?.url?.absoluteString ?? address.absoluteString, onOpen: {
                if $0 == address { state.webView?.load(URLRequest(url: $0)) }
                else { address = $0 }
                editingAddress = false
            }, onCancel: { editingAddress = false })
            .presentationDetents([.medium])
        }
    }
}
