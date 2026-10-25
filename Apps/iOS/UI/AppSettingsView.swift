import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var github = false
    @State private var ai = false
    var body: some View {
        NavigationStack {
            Form {
                Section("课程同步") { Button("GitHub 登录与设置") { github = true } }
                Section("讲一讲") { Button("AI 服务与提示词") { ai = true } }
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $github) { ConnectionView(model: model) }
            .sheet(isPresented: $ai) { AISettingsView() }
        }
    }
}
