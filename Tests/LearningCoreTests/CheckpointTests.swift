import XCTest
@testable import LearningCore

final class CheckpointTests:XCTestCase {
    func testSchemaModelsAndSharedGrade() throws {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/checkpoint.json")
        let question=try JSONDecoder().decode(CheckpointDefinition.self,from:Data(contentsOf:url))
        let engine=try CheckpointEngine()
        XCTAssertTrue(try engine.grade(question,selected:["one"]).correct)
        XCTAssertFalse(try engine.grade(question,selected:["two"]).correct)
        XCTAssertThrowsError(try engine.grade(question,selected:[]))
        let document=CourseDocument(kind:.note,path:"lesson.md",source:"# 课\n## 定义\n```checkpoint\n"+String(decoding:try JSONEncoder().encode(question),as:UTF8.self)+"\n```")
        let indexed=try engine.catalog([document])
        XCTAssertEqual(indexed.first?.question.id,question.id)
        XCTAssertThrowsError(try engine.catalog([document,document]))
    }
}
