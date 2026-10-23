import XCTest
@testable import LocalHTML

final class LocalHTMLTests: XCTestCase {
    func testSingleFileIsCopiedAndSurvivesOriginalRemoval() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("交互 %.HTML")
        try Data("<h1>Course</h1><script>localStorage.setItem('x','1')</script>".utf8).write(to: source)
        let store = LocalHTMLStore(directory: root.appendingPathComponent("library"))
        let draft = try store.prepare(source: source)
        let document = try store.accept(draft, entry: draft.entries[0])
        try FileManager.default.removeItem(at: source)
        let restored = try LocalHTMLStore(directory: store.directory).recent()
        XCTAssertEqual(restored?.id, document.id)
        XCTAssertEqual(try String(contentsOf: store.fileURL(for: document), encoding: .utf8), "<h1>Course</h1><script>localStorage.setItem('x','1')</script>")
    }

    func testFolderKeepsScriptsStylesImagesAndNestedPages() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("website")
        for (path, body) in ["index.html":"<script src='assets/app.js'></script>", "assets/app.js":"document.body.dataset.loaded='yes'", "assets/style.css":"body { color: green }", "assets/image.svg":"<svg/>", "pages/第二课.htm":"<img src='../assets/image.svg'>"] {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(body.utf8).write(to: url)
        }
        let store = LocalHTMLStore(directory: root.appendingPathComponent("library"))
        let draft = try store.prepare(source: folder)
        XCTAssertEqual(draft.entries, ["index.html", "pages/第二课.htm"])
        let document = try store.accept(draft, entry: "pages/第二课.htm")
        XCTAssertEqual(try String(contentsOf: store.rootURL(for: document).appendingPathComponent("assets/app.js"), encoding: .utf8), "document.body.dataset.loaded='yes'")
        XCTAssertEqual(try store.fileURL(for: document).lastPathComponent, "第二课.htm")
    }

    func testInvalidImportAndCancelledDraftKeepRecentDocument() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("first.html")
        try Data("<h1>First</h1>".utf8).write(to: source)
        let store = LocalHTMLStore(directory: root.appendingPathComponent("library"))
        let draft = try store.prepare(source: source)
        let original = try store.accept(draft, entry: "first.html")
        let cancelled = try store.prepare(source: source)
        XCTAssertThrowsError(try store.accept(cancelled, entry: "../first.html"))
        try store.discard(cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.directory.path))
        XCTAssertEqual(try store.recent()?.id, original.id)
        XCTAssertThrowsError(try store.prepare(source: root.appendingPathComponent("missing.html")))
        XCTAssertEqual(try store.recent()?.id, original.id)
    }

    func testReplacementAndClearRemoveOnlyImportedCopies() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("index.html")
        try Data("<h1>First</h1>".utf8).write(to: source)
        let store = LocalHTMLStore(directory: root.appendingPathComponent("library"))
        let first = try store.accept(store.prepare(source: source), entry: "index.html")
        let firstRoot = store.rootURL(for: first)
        let second = try store.accept(store.prepare(source: source), entry: "index.html")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstRoot.path))
        try store.clear()
        XCTAssertNil(try store.recent())
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.rootURL(for: second).path))
    }

    func testSymbolicLinksCannotEscapeImportedFolder() throws {
        let root = temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("website")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("<h1>Test</h1>".utf8).write(to: folder.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("outside"), withDestinationURL: root)
        let store = LocalHTMLStore(directory: root.appendingPathComponent("library"))
        XCTAssertThrowsError(try store.prepare(source: folder))
        XCTAssertNil(try store.recent())
    }

    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
}
