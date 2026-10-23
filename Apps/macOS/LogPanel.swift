import AppKit

@MainActor
final class LogPanel: NSScrollView {
    private let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 160))
    private var pending = ""
    private var flushTask: Task<Void, Never>?
    private let clock = DateFormatter()

    override init(frame: NSRect) {
        super.init(frame: frame)
        clock.dateFormat = "HH:mm:ss"
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 12, height: 8)
        text.minSize = NSSize(width: 0, height: 160)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
        documentView = text
        hasVerticalScroller = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func append(_ message: String, source: String) {
        let prefix = "[\(clock.string(from: Date()))] [\(source)] "
        pending += message.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }.map { prefix + $0 + "\n" }.joined()
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        let follow = text.bounds.height <= contentView.bounds.height ||
            contentView.bounds.maxY >= text.bounds.maxY - 24
        let attributes: [NSAttributedString.Key: Any] = [.font: text.font!, .foregroundColor: NSColor.labelColor]
        text.textStorage?.beginEditing()
        text.textStorage?.append(NSAttributedString(string: pending, attributes: attributes))
        pending = ""
        if let storage = text.textStorage, storage.length > 100_000 {
            let excess = storage.length - 80_000
            let range = (storage.string as NSString).lineRange(for: NSRange(location: 0, length: excess))
            storage.deleteCharacters(in: range)
        }
        text.textStorage?.endEditing()
        if follow { text.scrollToEndOfDocument(nil) }
    }
}
