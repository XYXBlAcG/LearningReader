import SwiftUI
import WebContent

struct LocalHTMLSection: View {
    @ObservedObject var model: WebWorkspaceModel
    @State private var search = ""
    @State private var renaming: HTMLDocument?
    @State private var title = ""
    var body: some View {
        Section("本地 HTML") {
            Button("导入 HTML 文件", systemImage: "doc.text") { model.picker = .file }.disabled(model.importing)
            Button("导入网页文件夹", systemImage: "folder") { model.picker = .folder }.disabled(model.importing)
            if model.importing { ProgressView("正在导入…"); Button("取消剩余导入") { model.stop() } }
            if !model.documents.isEmpty { TextField("搜索网页", text: $search) }
            ForEach(model.documents.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { recent in
                Button { model.open(recent) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recent.name)
                        Text("最近阅读 · " + recent.openedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(model.importing)
                .contextMenu {
                    Button("重命名") { renaming = recent; title = recent.name }
                    Button("移除导入副本", role: .destructive) { model.remove(recent) }
                }
            }
            ForEach(Array(model.importResults.enumerated()), id: \.offset) { _, result in Text(result).font(.caption).foregroundStyle(.secondary) }
            if !model.failedFiles.isEmpty {
                Button("重试失败文件") { model.importFiles(model.failedFiles) }.disabled(model.importing)
            }
        }
        .alert("网页名称", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $title)
            Button("保存") { if let document = renaming { model.rename(document, title: title) }; renaming = nil }
            Button("取消", role: .cancel) { renaming = nil }
        }
        Section {
            Button("打开网址", systemImage: "globe") { model.presentation = .address }.disabled(model.importing)
        }
    }
}
