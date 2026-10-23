import XCTest
import ZIPFoundation
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

    func testSourcesKeepStableIndependentIdentity() throws {
        let a = CourseSource.remote(repository: try Repository("a/course"), repositoryID: 1, branch: "main", configuration: .standard)
        let b = CourseSource.remote(repository: try Repository("b/course"), repositoryID: 2, branch: "main", configuration: .standard)
        let renamed = CourseSource.remote(repository: try Repository("a/renamed"), repositoryID: 1, branch: "main", configuration: .standard)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.id, renamed.id)
        XCTAssertNotEqual(a.id, CourseSource.remote(repository: try Repository("a/course"), repositoryID: 1, branch: "draft", configuration: .standard).id)
    }

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
