import SwiftUI
import UniformTypeIdentifiers
import LearningCore

struct CourseLibraryView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                ForEach(model.library.sources) { source in
                    HStack {
                        Button {
                            Task { await model.select(source); dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title)
                                Text(source.repository?.fullName ?? source.localPath ?? "本地课程").font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        if model.library.selectedID == source.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        Menu {
                            Button("移除课程及离线副本", role: .destructive) { Task { await model.remove(source) } }.disabled(model.syncing)
                        } label: { Image(systemName: "ellipsis") }
                    }.padding(.vertical, 4)
                }
                Button("添加课程", systemImage: "plus") { adding = true }
                #if os(iOS)
                LocalHTMLSection()
                #endif
            }
            .navigationTitle("课程仓库")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $adding) { AddCourseView(model: model) }
            .alert("课程仓库", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) { Button("知道了") { model.issue = nil } } message: { Text(model.issue ?? "") }
        }.frame(minWidth: 320, minHeight: 420)
    }
}

struct AddCourseView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var repository = ""
    @State private var branch = ""
    @State private var root = ""
    @State private var markdown = false
    @State private var exclusions = ""
    @State private var chooseLocal = false
    @State private var previewTask: Task<Void, Never>?
    private var excludedPaths: [String] { exclusions.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                if let draft = model.draft {
                    Section("课程预览") {
                        Text(draft.snapshot.course.manifest.title).font(.headline)
                        LabeledContent("文章", value: String(draft.snapshot.course.documents.count))
                        LabeledContent("来源", value: draft.source.repository?.fullName ?? "本地文件夹")
                        if draft.source.localPath == nil { LabeledContent("分支", value: draft.source.branch) }
                        Text(draft.snapshot.course.manifest.entry).font(.caption).foregroundStyle(.secondary)
                    }
                    Section("文件") {
                        ForEach(Array(draft.snapshot.course.documents.prefix(40).enumerated()), id: \.offset) { _, document in Text(document.path).font(.caption) }
                        if draft.snapshot.course.documents.count > 40 { Text("其余文章将在课程目录显示").foregroundStyle(.secondary) }
                    }
                    if !draft.snapshot.course.unresolved.isEmpty {
                        Section("待检查的知识链接") {
                            ForEach(Array(draft.snapshot.course.unresolved.prefix(10).enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption) }
                        }
                    }
                    Button("加入课程并阅读") { Task { await model.acceptDraft(); if model.issue == nil { dismiss() } } }.buttonStyle(.borderedProminent)
                    Button("返回修改") { model.discardDraft() }
                } else {
                    Section("GitHub 仓库") {
                        TextField("GitHub 地址或 owner/repository", text: $repository)
                        TextField("分支（留空使用默认分支）", text: $branch)
                        TextField("课程子目录（可留空）", text: $root)
                    }
                    Section {
                        Toggle("按 Markdown 导入（无 course.json）", isOn: $markdown)
                        if markdown { Text("从文件树阅读现有仓库；不修改上游内容。").font(.caption).foregroundStyle(.secondary) }
                        TextField("排除路径，每行一项", text: $exclusions, axis: .vertical).lineLimit(2...5)
                    }
                    Section {
                        Button("预览课程") {
                            previewTask = Task { await model.preview(repository: repository, branch: branch, root: root, markdown: markdown, excluding: excludedPaths) }
                        }.disabled(repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.preparing)
                        #if os(macOS)
                        Button("选择本地课程文件夹") { chooseLocal = true }.disabled(model.preparing)
                        #endif
                        if model.preparing { HStack { ProgressView().controlSize(.small); Text("正在下载并检查课程…") } }
                    }
                    Section {
                        Text("公共课程可直接读取。私有课程请先在 GitHub 设置中登录，并给 GitHub App 授权目标仓库。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("添加课程")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { previewTask?.cancel(); model.discardDraft(); dismiss() } } }
            .fileImporter(isPresented: $chooseLocal, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): previewTask = Task { await model.previewLocal(url, markdown: markdown, excluding: excludedPaths) }
                case .failure(let error): model.issue = error.localizedDescription
                }
            }
            .alert("添加课程", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) { Button("知道了") { model.issue = nil } } message: { Text(model.issue ?? "") }
        }
        .frame(minWidth: 320, minHeight: 460)
        .onDisappear { previewTask?.cancel(); model.discardDraft() }
    }
}
