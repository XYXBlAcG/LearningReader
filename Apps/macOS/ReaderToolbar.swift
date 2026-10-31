import AppKit
import LearningCore

@MainActor
final class ReaderToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "MathReaderToolbar")
    var onAction: ((String, NSView?) -> Void)?
    private var items: [String: NSToolbarItem] = [:]
    private let title = NSTextField(labelWithString: "知序")
    private let settings = NSPopUpButton(frame: .zero, pullsDown: true)
    private let more = NSPopUpButton(frame: .zero, pullsDown: true)
    private var ready = false
    private var busy = false
    private var projectReady = false
    var workflowAvailable = false { didSet { rebuildMenus() } }
    private var state: ReaderWebState?
    private let labels = ["courses": "课程仓库", "search": "搜索课程", "sidebar": "侧栏", "back": "返回", "forward": "前进", "history": "历史", "counterpart": "对应笔记或题目", "pin": "置顶", "settings": "阅读设置", "sync": "刷新课程"]
    private let symbols = ["courses": "books.vertical", "search": "magnifyingglass", "sidebar": "sidebar.left", "back": "chevron.left", "forward": "chevron.right", "history": "clock", "counterpart": "arrow.left.arrow.right", "pin": "pin", "sync": "arrow.triangle.2.circlepath"]

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        title.lineBreakMode = .byTruncatingMiddle
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        title.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ["courses", "sidebar", "back", "forward", "history", "title", "search", "counterpart", "pin", "settings", "sync", "more"].map { NSToolbarItem.Identifier($0) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let key = identifier.rawValue
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.autovalidates = false
        item.label = labels[key] ?? (key == "more" ? "更多" : "当前文档")
        item.toolTip = item.label
        if key == "title" {
            item.view = title
            item.visibilityPriority = .high
        } else if key == "settings" || key == "more" {
            let popup = key == "settings" ? settings : more
            popup.bezelStyle = .texturedRounded
            item.view = popup
        } else {
            item.image = NSImage(systemSymbolName: symbols[key] ?? "circle", accessibilityDescription: item.label)
            item.target = self
            item.action = #selector(activateItem(_:))
            item.visibilityPriority = ["back", "forward", "sync"].contains(key) ? .high : .standard
        }
        items[key] = item
        rebuildMenus()
        updateEnabled()
        return item
    }

    @objc private func activateItem(_ sender: NSToolbarItem) {
        onAction?(sender.itemIdentifier.rawValue, sender.view)
    }

    @objc private func activateMenu(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        onAction?(command, settings.superview)
    }

    func update(_ state: ReaderWebState) {
        self.state = state
        ready = true
        title.stringValue = state.title
        title.toolTip = state.path
        items["counterpart"]?.toolTip = state.counterpart
        items["pin"]?.image = NSImage(systemSymbolName: state.pinned ? "pin.fill" : "pin", accessibilityDescription: state.pinned ? "取消置顶" : "置顶")
        rebuildMenus()
        updateEnabled()
    }

    func setAvailability(project: Bool, busy: Bool, ready: Bool? = nil) {
        projectReady = project
        self.busy = busy
        if let ready { self.ready = ready }
        updateEnabled()
    }

    func setSyncStatus(_ message: String) {
        items["sync"]?.toolTip = message
    }

    private func updateEnabled() {
        for (key, item) in items {
            switch key {
            case "sync": item.isEnabled = projectReady && !busy
            case "back": item.isEnabled = ready && state?.canBack == true
            case "forward": item.isEnabled = ready && state?.canForward == true
            case "counterpart": item.isEnabled = ready && !(state?.counterpart.isEmpty ?? true)
            case "pin": item.isEnabled = ready && state?.hasDocument == true
            case "title", "more", "courses": item.isEnabled = true
            default: item.isEnabled = ready
            }
        }
        more.isEnabled = true
        settings.isEnabled = ready
        rebuildMenus()
    }

    private func rebuildMenus() {
        let reading = NSMenu()
        reading.autoenablesItems = false
        reading.addItem(withTitle: "阅读设置", action: nil, keyEquivalent: "")
        let choices: [(String, String, Bool)] = [
            ("本页目录", "outline", state?.outline == true),
            ("知识关联", "graph", state?.panel == "graph" && state?.outline == true),
            ("课程术语库", "glossary", false),
            ("三维预览", "previews", state?.previews == true),
            ("沉浸阅读", "immersive", state?.immersive == true),
            ("放大正文（\(Int((state?.zoom ?? 1) * 100))%）", "zoomIn", false),
            ("缩小正文", "zoomOut", false),
            ("上一篇（[）", "previous", false), ("下一篇（]）", "next", false)
        ]
        for (label, command, checked) in choices {
            let item = NSMenuItem(title: label, action: #selector(activateMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command
            item.state = checked ? .on : .off
            item.isEnabled = ready
            reading.addItem(item)
        }
        settings.menu = reading
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "更多", action: nil, keyEquivalent: "")
        for (label, command) in [("刷新课程", "sync"), ("课程仓库…", "courses"), ("添加课程…", "add"), ("打开本地课程…", "project"), ("GitHub 设置…", "connection"), ("运行本地课程工作流…", "workflow"), ("显示或隐藏日志", "logs")] {
            let item = NSMenuItem(title: label, action: #selector(activateMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command
            item.isEnabled = command == "workflow" ? workflowAvailable && !busy : (["logs", "courses", "add", "project", "connection"].contains(command) || (!busy && projectReady))
            menu.addItem(item)
        }
        more.menu = menu
    }
}
