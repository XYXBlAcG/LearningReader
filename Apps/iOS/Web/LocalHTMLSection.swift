import SwiftUI

struct LocalHTMLSection: View {
    @ObservedObject var model: WebWorkspaceModel
    var body: some View {
        Section("本地 HTML") {
            Button("打开 HTML 文件", systemImage: "doc.text") { model.picker = .file }.disabled(model.importing)
            Button("导入网页文件夹", systemImage: "folder") { model.picker = .folder }.disabled(model.importing)
            if model.importing { ProgressView("正在导入…") }
            if let recent = model.recent {
                Button { model.openRecent() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recent.name)
                        Text("最近阅读 · " + recent.openedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(model.importing)
                .contextMenu { Button("移除导入副本", role: .destructive) { model.clear() }.disabled(model.importing) }
            }
        }
        Section {
            Button("打开网址", systemImage: "globe") { model.presentation = .address }.disabled(model.importing)
        }
    }
}
