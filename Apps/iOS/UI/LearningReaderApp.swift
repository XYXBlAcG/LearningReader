import SwiftUI
import LearningCore

@main
struct LearningReaderApp: App {
    @StateObject private var model = ReaderModel()
    @StateObject private var ai = AIWorkspace()
    var body: some Scene {
        WindowGroup {
            LearningView(model: model)
                .environmentObject(ai)
                .frame(minWidth: 320, minHeight: 420)
                .preferredColorScheme(.light)
        }
    }
}

struct LearningView: View {
    @ObservedObject var model: ReaderModel
    @StateObject private var reader = ReaderController()
    @StateObject private var interaction = AIInteraction()
    @EnvironmentObject private var ai: AIWorkspace
    @Environment(\.scenePhase) private var scenePhase
    @State private var courses = false
    @State private var settings = false
    @State private var history = false
    @State private var tools = false
    @State private var columns:NavigationSplitViewVisibility = .automatic
    @State private var compactColumn:NavigationSplitViewColumn = .detail
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationSplitView(columnVisibility:$columns,preferredCompactColumn:$compactColumn) {
            if let snapshot=model.snapshot {
                NativeCourseSidebar(snapshot:snapshot,reader:reader,onCourses:{courses=true},onOpen:open).id(snapshot.id)
            } else {
                List { Button("课程仓库",systemImage:"books.vertical") { courses=true } }.navigationTitle("课程目录")
            }
        } detail: {
            Group {
                if let snapshot = model.snapshot, let source = model.selected {
                    ReaderSurface(snapshot: snapshot, sourceID: source.id, legacy: model.legacyReadingState, legacyState: model.legacyState, controller: reader, onError: { model.issue = $0 }).id(source.id + snapshot.id)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "book.pages").font(.system(size: 48)).foregroundStyle(.tint)
                        Text(model.selected?.title ?? "知序").font(.title)
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                        Button("添加或切换课程") { courses = true }.buttonStyle(.borderedProminent)
                        Button("设置") { settings = true }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(reader.state?.title ?? model.selected?.title ?? "知序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button { reader.send("back") } label: { Image(systemName:"arrow.uturn.backward") }
                        .disabled(reader.state?.canBack != true).accessibilityLabel("返回原文")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button { tools.toggle() } label: { Image(systemName:"sidebar.right") }
                        .accessibilityLabel("本页目录与知识关联")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("搜索", systemImage: "magnifyingglass") { compactColumn = .sidebar;columns = .all }
                        Button("前进", systemImage: "chevron.right") { reader.send("forward") }.disabled(reader.state?.canForward != true)
                        Button("历史记录", systemImage: "clock") { history = true }
                        Section("讲一讲") {
                            Button("拍照提问", systemImage: "camera") { interaction.media = .camera }
                            Button("选择图片", systemImage: "photo") { interaction.media = .library }
                        }
                        Button("对应笔记或练习", systemImage: "arrow.left.arrow.right") { reader.send("counterpart") }.disabled(reader.state?.counterpart.isEmpty != false)
                        Button(reader.state?.pinned == true ? "取消置顶" : "置顶本页", systemImage: "pin") { reader.send("pin") }
                        Section("阅读") {
                            Button("放大正文", systemImage: "textformat.size.larger") { reader.send("zoomIn") }
                            Button("缩小正文", systemImage: "textformat.size.smaller") { reader.send("zoomOut") }
                            Button(reader.state?.previews == true ? "关闭三维预览" : "开启三维预览", systemImage: "cube") { reader.send("previews") }
                        }
                        Section {
                            Button("刷新课程", systemImage: "arrow.clockwise") { model.sync() }.disabled(model.syncing || model.selected == nil)
                            Button("课程仓库", systemImage: "books.vertical") { courses = true }
                            Button("设置", systemImage: "gearshape") { settings = true }
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
            .inspector(isPresented:$tools) {
                ReaderToolsView(snapshot:model.snapshot,reader:reader,presented:$tools,onOpen:open)
            }
            .sheet(isPresented: $courses) { CourseLibraryView(model: model) }
            .sheet(isPresented: $settings) { AppSettingsView(model: model) }
            .sheet(isPresented: $history) { ReadingHistoryView(reader: reader) }
            .alert("知序", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) {
                Button("知道了") { model.issue = nil }
            } message: { Text(model.issue ?? "") }
            .task {
                reader.onSelection = { interaction.begin($0, workspace: ai) }
                reader.selectionActions=ai.settings.actions
                await model.start()
            }
            .onReceive(ai.$settings) { reader.selectionActions=$0.actions }
            .onChange(of: model.library.selectedID) { _ in reader.state = nil }
            .onChange(of: scenePhase) { value in if value == .active { model.sync(automatic: true) } }
        }
        .tint(Color(red: 0.06, green: 0.59, blue: 0.46))
        .modifier(AIHost(interaction: interaction))
    }
    private func open(_ target:ReaderDocumentTarget) {
        reader.open(target)
        compactColumn = .detail
        if sizeClass == .compact { tools=false }
    }

}
