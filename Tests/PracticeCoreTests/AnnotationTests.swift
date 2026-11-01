import XCTest
import AICore
@testable import PracticeCore
final class AnnotationTests:XCTestCase {
    func testColoredNotesRoundTripAndDeletionIsIndependent() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:url)}
        let store=try AnnotationStore(url:url)
        var item=CourseAnnotation(source:.init(courseID:"c",kind:"note",path:"lesson.md"),quote:"连续函数",color:"#55AAFF")
        item.note="我的理解";try store.save(item)
        let loaded=try AnnotationStore(url:url)
        XCTAssertEqual(loaded.items.first?.note,"我的理解")
        XCTAssertEqual(loaded.items.first?.color,"#55AAFF")
        try loaded.delete(item.id);XCTAssertTrue(loaded.items.isEmpty)
        item.color="invalid";XCTAssertThrowsError(try loaded.save(item))
    }
}

extension AnnotationTests {
    func testEmptySelectionAndWebSourcesCannotBeWrittenAsCourseHighlights() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:url)}
        let store=try AnnotationStore(url:url)
        let web=CourseAnnotation(source:.init(courseID:"c",kind:"web",path:"https://example.org"),quote:"文字")
        XCTAssertThrowsError(try store.save(web))
        let empty=CourseAnnotation(source:.init(courseID:"c",kind:"note",path:"lesson.md"),quote:"   ")
        XCTAssertThrowsError(try store.save(empty))
        XCTAssertTrue(store.items.isEmpty)
    }
}
