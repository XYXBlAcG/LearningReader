import XCTest
import ZIPFoundation
#if os(macOS)
import SQLite3
#endif
@testable import LearningCore

final class CourseTests: XCTestCase {
    func testBothTemplatesValidateThroughRealIndexer() throws {
        for name in ["minimal-course", "machine-learning-course"] {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Templates/" + name)
            let result = try CourseIndexer.build(root: root, configuration: .standard)
            XCTAssertFalse(result.documents.isEmpty)
            XCTAssertTrue(result.unresolved.isEmpty)
        }
    }

    func testImportExcludesBuildDirectoriesAndUsesFullPaths() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let course = try CourseIndexer.build(root: root, configuration: .markdown(root: "lessons", excluding: []))
        XCTAssertEqual(Set(course.documents.map(\.path)), ["one.md"])
        XCTAssertEqual(course.manifest.entry, "one.md")
    }

    func testArchiveInstallationIsAtomicAndRepositoryScoped() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("course.zip")
        try FileManager.default.zipItem(at: root.appendingPathComponent("lessons"), to: zip)
        let store = SnapshotStore(directory: root.appendingPathComponent("store"))
        let a = try store.install(archive: zip, revision: String(repeating: "a", count: 40), configuration: .markdown(root: "", excluding: []))
        XCTAssertEqual(a.course.documents.count, 1)
        XCTAssertThrowsError(try store.install(archive: zip, revision: "../bad", configuration: .standard))
        XCTAssertEqual(try store.current()?.revision, a.revision)
        XCTAssertThrowsError(try a.resource(path: "/media/../current.json"))
        XCTAssertThrowsError(try a.resource(path: "/media/.github/secrets"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try a.resource(path: "/content/note/one.md").path))
    }

    func testStandardCourseRejectsMissingEntryOverlapsAndEscapingResources() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for manifest in [
            "{\"schemaVersion\":1,\"title\":\"T\",\"entry\":\"missing.md\",\"sections\":[{\"kind\":\"note\",\"path\":\"lessons\",\"title\":\"课程\"}],\"assets\":[]}",
            "{\"schemaVersion\":1,\"title\":\"T\",\"entry\":\"lessons/one.md\",\"sections\":[{\"kind\":\"note\",\"path\":\"lessons\",\"title\":\"课程\"},{\"kind\":\"exercise\",\"path\":\"lessons\",\"title\":\"练习\"}],\"assets\":[]}",
            "{\"schemaVersion\":1,\"title\":\"T\",\"entry\":\"lessons/one.md\",\"sections\":[{\"kind\":\"note\",\"path\":\"lessons\",\"title\":\"课程\"}],\"assets\":[\"../private\"]}"
        ] {
            try Data(manifest.utf8).write(to: root.appendingPathComponent("course.json"))
            XCTAssertThrowsError(try CourseIndexer.build(root: root, configuration: .standard))
        }
    }

    func testCancelledBackgroundInstallCannotReplaceCurrentSnapshot() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("course.zip")
        try FileManager.default.zipItem(at: root.appendingPathComponent("lessons"), to: zip)
        let store = SnapshotStore(directory: root.appendingPathComponent("store"))
        let configuration = ImportConfiguration.markdown(root: "", excluding: [])
        let original = try store.install(archive: zip, revision: String(repeating: "a", count: 40), configuration: configuration)
        let cancelled = Task {
            try await BackgroundWork.run {
                Thread.sleep(forTimeInterval: 0.05)
                return try store.install(archive: zip, revision: String(repeating: "b", count: 40), configuration: configuration)
            }
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled installation succeeded") }
        catch is CancellationError { }
        XCTAssertEqual(try store.current()?.revision, original.revision)
    }

    func testExtraRootDocumentsUseCanonicalCoursePaths() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# 写作规范".utf8).write(to: root.appendingPathComponent("writing.md"))
        let manifest = CourseManifest(schemaVersion: 1, title: "Course", entry: "lessons/one.md", sections: [.init(kind: .note, path: "lessons", title: "课程")], assets: [], documents: ["writing.md"])
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("course.json"))
        XCTAssertEqual(Set(try CourseIndexer.build(root: root, configuration: .standard).documents.map(\.path)), ["lessons/one.md", "writing.md"])
    }

    func testSourcesKeepStableIndependentIdentity() throws {
        let a = CourseSource.remote(repository: try Repository("a/course"), repositoryID: 1, branch: "main", configuration: .standard)
        let b = CourseSource.remote(repository: try Repository("b/course"), repositoryID: 2, branch: "main", configuration: .standard)
        let renamed = CourseSource.remote(repository: try Repository("a/renamed"), repositoryID: 1, branch: "main", configuration: .standard)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.id, renamed.id)
        XCTAssertNotEqual(a.id, CourseSource.remote(repository: try Repository("a/course"), repositoryID: 1, branch: "draft", configuration: .standard).id)
    }

    #if os(macOS)
    func testDesktopMigrationReadsOnlyMatchingOriginAndReaderKeys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("origin/LocalStorage")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var origin = Data([4, 0, 0, 0, 1])
        origin.append(Data("http".utf8)); origin.append(contentsOf: [9, 0, 0, 0, 1])
        origin.append(Data("127.0.0.1".utf8)); origin.append(contentsOf: [1, 80, 0]); origin.append(origin)
        try origin.write(to: directory.deletingLastPathComponent().appendingPathComponent("origin"))
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("localstorage.sqlite3").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ItemTable(key TEXT, value BLOB); INSERT INTO ItemTable VALUES('reader_zoom', X'3100'); INSERT INTO ItemTable VALUES('other', X'3200');", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(LegacyDesktopState.read(directory: root, port: 80), ["reader_zoom": "1"])
        XCTAssertTrue(LegacyDesktopState.read(directory: root, port: 81).isEmpty)
    }
    #endif

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (path, value) in ["lessons/one.md":"# 入门\n理解模型", "lessons/node_modules/bad.md":"# 依赖"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: url)
        }
        return root
    }
}
