import AppKit
import LearningCore

@MainActor
final class HistoryPanel: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onOpen: ((ReaderWebState.Visit) -> Void)?
    var onClear: (() -> Void)?
    private let search = NSSearchField()
    private let table = NSTableView()
    private let empty = NSTextField(labelWithString: "暂无阅读记录")
    private var visits: [ReaderWebState.Visit] = []
    private var filtered: [ReaderWebState.Visit] = []

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("document"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 60
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(openVisit)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        search.placeholderString = "搜索历史文档…"
        search.delegate = self
        let clear = NSButton(title: "清空历史", target: self, action: #selector(clearVisits))
        let heading = NSTextField(labelWithString: "阅读历史")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let header = NSStackView(views: [heading, NSView(), clear])
        header.distribution = .fill
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        empty.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [header, search, empty, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view = stack
        preferredContentSize = NSSize(width: 420, height: 480)
        for child in [header, search, empty, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
    }

    func update(_ visits: [ReaderWebState.Visit]) {
        _ = view
        self.visits = visits
        filter()
    }

    func controlTextDidChange(_ obj: Notification) { filter() }

    private func filter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = visits.filter { query.isEmpty || ($0.label + $0.path).localizedCaseInsensitiveContains(query) }
        empty.stringValue = query.isEmpty ? "暂无阅读记录" : "没有匹配的记录"
        empty.isHidden = !filtered.isEmpty
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let visit = filtered[row]
        let date = Date(timeIntervalSince1970: visit.time / 1000).formatted(date: .abbreviated, time: .shortened)
        let label = NSTextField(wrappingLabelWithString: visit.label + "\n" + (visit.kind == "note" ? "笔记" : "练习") + " · " + date + (visit.missing ? " · 文件已不存在" : ""))
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = visit.path
        return label
    }

    @objc private func openVisit() {
        let row = table.selectedRow
        guard filtered.indices.contains(row) else { return }
        onOpen?(filtered[row])
    }

    @objc private func clearVisits() { onClear?() }
}
