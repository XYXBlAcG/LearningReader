import AppKit
import SwiftUI
import Combine
import LearningCore

@main
struct LearningReaderApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = DesktopApplication()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) { }
    }
}

@MainActor
final class DesktopPresentation: ObservableObject {
    enum Panel: String, Identifiable {
        case courses, add, account
        var id: String { rawValue }
    }
    @Published var panel: Panel?
}

struct DesktopContent: View {
    @ObservedObject var model: ReaderModel
    @ObservedObject var reader: ReaderController
    @ObservedObject var presentation: DesktopPresentation

    var body: some View {
        Group {
            if let snapshot = model.snapshot, let source = model.selected {
                ReaderSurface(snapshot: snapshot, sourceID: source.id, legacy: model.legacyReadingState, legacyState: model.legacyState, controller: reader, onError: { model.issue = $0 }).id(source.id + snapshot.id)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "books.vertical").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text(model.selected?.title ?? "知序").font(.title2)
                    Text(model.status).foregroundStyle(.secondary)
                    Button("打开课程仓库") { presentation.panel = .courses }.keyboardShortcut("o")
                    Button("添加课程") { presentation.panel = .add }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $presentation.panel) { panel in
            Group {
                switch panel {
                case .courses: CourseLibraryView(model: model)
                case .add: AddCourseView(model: model)
                case .account: ConnectionView(model: model)
                }
            }.frame(width: 600, height: 560)
        }
        .alert("知序", isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })) {
            Button("知道了") { model.issue = nil }
        } message: { Text(model.issue ?? "") }
        .preferredColorScheme(.light)
        .tint(Color(red: 0.06, green: 0.59, blue: 0.46))
    }
}

@MainActor
final class DesktopApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = ReaderModel()
    private let reader = ReaderController()
    private let presentation = DesktopPresentation()
    private let controls = ReaderToolbar()
    private let history = HistoryPanel()
    private let historyPopover = NSPopover()
    private let logs = LogPanel(frame: .zero)
    private let status = NSTextField(labelWithString: "准备课程…")
    private let progress = NSProgressIndicator()
    private var window: NSWindow!
    private var subscriptions = Set<AnyCancellable>()
    private var selectedID: String?
    private var lastStatus = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "知序"
        window.minSize = NSSize(width: 740, height: 500)
        window.setFrameAutosaveName("MathReaderWindow")
        window.toolbarStyle = .unified
        window.toolbar = controls.toolbar
        window.delegate = self
        window.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: DesktopContent(model: model, reader: reader, presentation: presentation))
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        let footer = NSStackView(views: [progress, status, NSView()])
        footer.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        let stack = NSStackView(views: [content, logs, footer])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        window.contentView = stack
        for child in [content, logs, footer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        logs.heightAnchor.constraint(equalToConstant: 180).isActive = true
        logs.isHidden = true
        content.setContentHuggingPriority(.defaultLow, for: .vertical)
        controls.onAction = { [weak self] command, anchor in self?.perform(command, anchor: anchor) }
        historyPopover.behavior = .transient
        historyPopover.contentViewController = history
        history.onOpen = { [weak self] visit in
            guard !visit.missing else { return }
            self?.reader.send("openHistory", payload: ["kind": visit.kind, "path": visit.path])
            self?.historyPopover.close()
        }
        history.onClear = { [weak self] in self?.reader.send("clearHistory") }
        model.objectWillChange.sink { [weak self] in Task { @MainActor in self?.refresh() } }.store(in: &subscriptions)
        reader.$state.sink { [weak self] state in
            guard let self, let state else { return }
            self.controls.update(state)
            self.history.update(state.history)
            self.window.title = state.title + " — 知序"
        }.store(in: &subscriptions)
        model.$workflowLog.compactMap { $0 }.sink { [weak self] output in
            self?.logs.append(output, source: "课程工作流")
            self?.logs.isHidden = false
        }.store(in: &subscriptions)
        buildMenus()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { await model.start(); refresh() }
    }

    private func refresh() {
        if selectedID != model.library.selectedID {
            selectedID = model.library.selectedID
            reader.state = nil
            history.update([])
            historyPopover.close()
            window.title = (model.selected?.title ?? "知序") + " — 知序"
        }
        status.stringValue = model.status
        if lastStatus != model.status { logs.append(model.status, source: "课程"); lastStatus = model.status }
        if model.syncing || model.workflowRunning { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        controls.workflowAvailable = model.selected?.localPath != nil && model.snapshot?.course.manifest.workflow != nil
        controls.setAvailability(project: model.selected != nil, busy: model.syncing || model.authenticating || model.workflowRunning, ready: reader.state != nil && model.snapshot != nil)
        controls.setSyncStatus(model.status)
    }

    private func perform(_ command: String, anchor: NSView? = nil) {
        switch command {
        case "courses": presentation.panel = .courses
        case "add": presentation.panel = .add
        case "connection": presentation.panel = .account
        case "project":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "打开课程"
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                Task { @MainActor in
                    guard let self else { return }
                    await self.model.previewLocal(url, markdown: !FileManager.default.fileExists(atPath: url.appendingPathComponent("course.json").path), excluding: [])
                    if self.model.draft != nil { self.presentation.panel = .add }
                }
            }
        case "sync": model.sync()
        case "search": reader.search()
        case "history":
            if historyPopover.isShown { historyPopover.close(); return }
            let view = anchor ?? window.contentView!
            history.update(reader.state?.history ?? [])
            historyPopover.show(relativeTo: NSRect(x: min(220, view.bounds.width / 2), y: view.bounds.maxY, width: 1, height: 1), of: view, preferredEdge: .minY)
        case "logs": logs.isHidden.toggle()
        case "workflow":
            guard !model.workflowRunning, let workflow = model.snapshot?.course.manifest.workflow, model.selected?.localPath != nil else { return }
            let alert = NSAlert()
            alert.messageText = workflow.title
            alert.informativeText = ([workflow.program] + workflow.arguments).joined(separator: " ")
            alert.addButton(withTitle: "运行")
            alert.addButton(withTitle: "取消")
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { Task { @MainActor in await self?.model.runWorkflow() } }
            }
        default: reader.send(command)
        }
    }

    private func buildMenus() {
        let main = NSMenu()
        let application = NSMenu()
        application.addItem(withTitle: "关于知序", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "隐藏知序", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(withTitle: "退出知序", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = application; main.addItem(appItem)
        let file = NSMenu(title: "文件")
        for (title, command, key) in [("课程仓库…", "courses", "o"), ("添加课程…", "add", "n"), ("打开本地课程…", "project", ""), ("GitHub 设置…", "connection", ","), ("刷新课程", "sync", "r"), ("运行本地课程工作流…", "workflow", "")] {
            let item = file.addItem(withTitle: title, action: #selector(menuAction(_:)), keyEquivalent: key)
            item.target = self; item.representedObject = command
        }
        let fileItem = NSMenuItem(); fileItem.submenu = file; main.addItem(fileItem)
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        let reading = NSMenu(title: "阅读")
        for (title, command, key) in [("搜索课程", "search", "f"), ("返回", "back", "["), ("前进", "forward", "]"), ("历史记录", "history", "y"), ("课程目录", "sidebar", ""), ("本页目录", "outline", ""), ("知识关联", "graph", ""), ("课程术语库", "glossary", ""), ("放大正文", "zoomIn", "+"), ("缩小正文", "zoomOut", "-"), ("显示或隐藏日志", "logs", "")] {
            let item = reading.addItem(withTitle: title, action: #selector(menuAction(_:)), keyEquivalent: key)
            item.target = self; item.representedObject = command
        }
        let readingItem = NSMenuItem(); readingItem.submenu = reading; main.addItem(readingItem)
        NSApplication.shared.mainMenu = main
    }

    @objc private func menuAction(_ sender: NSMenuItem) { if let command = sender.representedObject as? String { perform(command) } }

    func applicationDidBecomeActive(_ notification: Notification) { model.sync(automatic: true) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.workflowRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "课程工作流仍在运行"
        alert.informativeText = "请等待工作流完成后退出。"
        alert.runModal()
        return .terminateCancel
    }
}
