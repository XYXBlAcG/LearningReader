import SwiftUI
import WebContent

struct WebAddressScreen: View {
    @State private var address: String
    @State private var issue: String?
    @FocusState private var focused: Bool
    let onOpen: (URL) -> Void
    let onCancel: () -> Void

    init(initial: String, onOpen: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        _address = State(initialValue: initial)
        self.onOpen = onOpen
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("网址", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(openAddress)
                if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            }
            .navigationTitle("输入网址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("打开", action: openAddress).disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .task { focused = true }
        }
    }

    private func openAddress() {
        do { onOpen(try WebAddress.parse(address)) }
        catch { issue = error.localizedDescription }
    }
}
