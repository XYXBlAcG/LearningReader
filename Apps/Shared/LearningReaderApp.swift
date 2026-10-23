import SwiftUI
import LearningCore

@main
struct LearningReaderApp: App {
    @StateObject private var model = ReaderModel()
    var body: some Scene {
        WindowGroup {
            LearningView(model: model)
                .frame(minWidth: 320, minHeight: 420)
                .preferredColorScheme(.light)
        }
    }
}

struct LearningView: View {
    @ObservedObject var model: ReaderModel
    @StateObject private var reader = ReaderController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var courses = false
    @State private var settings = false
    @State private var history = false

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = model.snapshot, let source = model.selected {
                    ReaderSurface(snapshot: snapshot, sourceID: source.id, legacy: model.legacyReadingState, controller: reader, onError: { model.issue = $0 }).id(source.id + snapshot.id)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "book.pages").font(.system(size: 48)).foregroundStyle(.tint)
                        Text(model.selected?.title ?? "知序").font(.title)
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                        Button("添加或切换课程") { courses = true }.buttonStyle(.borderedProminent)
                        Button("GitHub 登录与设置") { settings = true }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(reader.state?.title ?? model.selected?.title ?? "知序")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button { courses = true } label: { Image(systemName: "books.vertical") }.help("课程仓库")
                    Button { reader.send("sidebar") } label: { Image(systemName: "sidebar.left") }.help("课程目录")
                    Button { reader.send("back") } label: { Image(systemName: "chevron.left") }.disabled(reader.state?.canBack != true).help("返回原文")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("搜索", systemImage: "magnifyingglass") { reader.search() }
                        Button("前进", systemImage: "chevron.right") { reader.send("forward") }.disabled(reader.state?.canForward != true)
                        Button("历史记录", systemImage: "clock") { history = true }
                        Button("对应笔记或练习", systemImage: "arrow.left.arrow.right") { reader.send("counterpart") }.disabled(reader.state?.counterpart.isEmpty != false)
                        Button(reader.state?.pinned == true ? "取消置顶" : "置顶本页", systemImage: "pin") { reader.send("pin") }
                        Section("阅读") {
                            Button("放大正文", systemImage: "textformat.size.larger") { reader.send("zoomIn") }
                            Button("缩小正文", systemImage: "textformat.size.smaller") { reader.send("zoomOut") }
                            Button("本页目录", systemImage: "list.bullet") { reader.send("outline") }
                            Button("知识关联", systemImage: "point.3.connected.trianglepath.dotted") { reader.send("graph") }
                            Button(reader.state?.previews == true ? "关闭三维预览" : "开启三维预览", systemImage: "cube") { reader.send("previews") }
                        }
                        Section {
                            Button("刷新课程", systemImage: "arrow.clockwise") { model.sync() }.disabled(model.syncing || model.selected == nil)
                            Button("课程仓库", systemImage: "books.vertical") { courses = true }
                            Button("GitHub 设置", systemImage: "gearshape") { settings = true }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.help("阅读与同步设置")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 8) {
                    if model.syncing { ProgressView().controlSize(.small) }
                    Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { model.sync() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.syncing || model.selected == nil)
                }.padding(.horizontal, 14).padding(.vertical, 7).background(.bar)
            }
            .sheet(isPresented: $courses) { CourseLibraryView(model: model) }
            .sheet(isPresented: $settings) { ConnectionView(model: model) }
            .sheet(isPresented: $history) { ReadingHistoryView(reader: reader) }
            .alert("知序", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) {
                Button("知道了") { model.issue = nil }
            } message: { Text(model.issue ?? "") }
            .task { await model.start() }
            .onChange(of: model.library.selectedID) { _ in reader.state = nil }
            .onChange(of: scenePhase) { value in if value == .active { model.sync(automatic: true) } }
        }
        .tint(Color(red: 0.06, green: 0.59, blue: 0.46))
    }
}

struct ReadingHistoryView: View {
    @ObservedObject var reader: ReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array((reader.state?.history ?? []).enumerated()), id: \.offset) { _, visit in
                    if query.isEmpty || visit.label.localizedCaseInsensitiveContains(query) {
                        Button {
                            reader.send("openHistory", payload: ["kind": visit.kind, "path": visit.path])
                            dismiss()
                        } label: { Text(visit.label) }.disabled(visit.missing)
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索阅读历史")
            .navigationTitle("历史记录")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.frame(minWidth: 300, minHeight: 360)
    }
}
