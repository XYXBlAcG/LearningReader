import XCTest
@testable import WebContent

final class HTMLLibraryTests: XCTestCase {
    func testMultipleImportsSurviveReopenAndIndividualRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("same.html")
        try Data("hello".utf8).write(to: source)
        let store = LocalHTMLStore(directory: root.appendingPathComponent("library"))
        let first = try store.accept(store.prepare(source: source), entry: "same.html")
        let second = try store.accept(store.prepare(source: source), entry: "same.html")
        XCTAssertEqual(try store.documents().count, 2)
        XCTAssertNotEqual(first.id, second.id)
        try store.rename(first, title: "第一课")
        let reopened = LocalHTMLStore(directory: store.directory)
        XCTAssertEqual(try reopened.documents().first(where: { $0.id == first.id })?.name, "第一课")
        try reopened.remove(second)
        XCTAssertEqual(try reopened.documents().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try reopened.fileURL(for: first).path))
    }

    func testLegacyRecentRecordMigratesWithoutChangingIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalHTMLStore(directory: root)
        let old = HTMLDocument(id: UUID(), entry: "old.html", openedAt: Date())
        try FileManager.default.createDirectory(at: store.rootURL(for: old), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: store.rootURL(for: old).appendingPathComponent("old.html"))
        try JSONEncoder().encode(old).write(to: root.appendingPathComponent("recent.json"))
        XCTAssertEqual(try store.documents().map(\.id), [old.id])
        XCTAssertEqual(try store.markOpened(old).id, old.id)
    }
}
