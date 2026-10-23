import SwiftUI
import UniformTypeIdentifiers

struct LocalHTMLSection: View {
    @StateObject private var model = LocalHTMLModel()
    @State private var picking = false
    @State private var folder = false

    var body: some View {
        Section("本地 HTML") {
            Button("打开 HTML 文件", systemImage: "doc.text") { folder = false; picking = true }.disabled(model.importing)
            Button("导入网页文件夹", systemImage: "folder") { folder = true; picking = true }.disabled(model.importing)
            if model.importing { ProgressView("正在导入…") }
            if let recent = model.recent {
                Button { model.openRecent() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recent.name)
                        Text("最近阅读 · " + recent.openedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contextMenu { Button("移除导入副本", role: .destructive) { model.clear() } }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: folder ? [.folder] : [.html]) { result in
            switch result {
            case .success(let url): model.importFile(url)
            case .failure(let error): model.issue = error.localizedDescription
            }
        }
        .fullScreenCover(item: $model.presentation, onDismiss: model.discardPending) { presentation in
            switch presentation {
            case .choose(let draft):
                NavigationStack {
                    List(draft.entries, id: \.self) { entry in Button(entry) { model.choose(entry) } }
                        .navigationTitle("选择网页")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { model.presentation = nil } } }
                        .alert("本地 HTML", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) { Button("知道了") { model.issue = nil } } message: { Text(model.issue ?? "") }
                }
            case .read(let document, let file, let root):
                HTMLReaderScreen(document: document, file: file, root: root)
            }
        }
        .alert("本地 HTML", isPresented: Binding(get: { model.issue != nil && model.presentation == nil }, set: { if !$0 { model.issue = nil } })) { Button("知道了") { model.issue = nil } } message: { Text(model.issue ?? "") }
        .onDisappear { if model.presentation == nil { model.discardPending() } }
    }
}
