import XCTest
@testable import LearningCore

final class GlossaryTests: XCTestCase {
    func testFolderIsIndexedSeparatelyAndAvailableToOfflineReader() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("术语"), withIntermediateDirectories: true)
        try Data("# 课程\n\n## 定义\n例子".utf8).write(to: root.appendingPathComponent("lesson.md"))
        let term = """
        # 连续函数

        ```glossary
        {"id":"calculus.continuity","term":"连续函数","aliases":[],"subject":"微积分","related":[],"notes":[{"kind":"note","path":"lesson.md","anchor":"定义"}]}
        ```

        ## 直觉
        输入的小变化不会造成输出突变。

        ## 定义
        函数在点处的极限等于函数值。

        ## 例子
        多项式在实数上连续。
        """
        try Data(term.utf8).write(to: root.appendingPathComponent("术语/连续.md"))
        let store = SnapshotStore(directory: root.appendingPathComponent(".tmp/store"))
        let snapshot = try store.openLocal(root: root, configuration: .markdown(root: "", excluding: []))
        XCTAssertEqual(snapshot.course.documents.map(\.path), ["lesson.md"])
        let data = try Data(contentsOf: snapshot.resource(path: "/content/glossary.json"))
        let library = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((library["terms"] as? [[String: Any]])?.count, 1)
        try Data(term.replacingOccurrences(of: "\"anchor\":\"定义\"", with: "\"anchor\":\"不存在\"").utf8).write(to: root.appendingPathComponent("术语/连续.md"))
        XCTAssertThrowsError(try store.openLocal(root: root, configuration: .markdown(root: "", excluding: [])))
    }

    func testExcludingRootAuthoringFilesDoesNotSkipCourseDirectories() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root.appendingPathComponent("lessons"),withIntermediateDirectories:true)
        try Data("# Rules".utf8).write(to:root.appendingPathComponent("AGENTS.md"))
        try Data("# Lesson".utf8).write(to:root.appendingPathComponent("lessons/one.md"))
        let manifest=CourseManifest(schemaVersion:1,title:"Course",entry:"lessons/one.md",sections:[.init(kind:.note,path:"lessons",title:"课程")],assets:[],exclude:["AGENTS.md"])
        try JSONEncoder().encode(manifest).write(to:root.appendingPathComponent("course.json"))
        let result=try CourseIndexer.build(root:root,configuration:.standard)
        XCTAssertEqual(result.documents.map(\.path),["lessons/one.md"])
    }

    func testEmptyCourseGlossaryIsValid() throws {
        let data = try CourseGlossary.build(root: FileManager.default.temporaryDirectory, available: [], documents: [])
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((object["terms"] as? [Any])?.count, 0)
    }
}
