import XCTest
import AICore
@testable import PracticeCore
final class PracticeTests:XCTestCase {
    func testInvalidRatingAndCorruptArchiveAreReported() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:url)}
        let store=try PracticeStore(url:url)
        let id=try store.capture(title:"概念",question:"定义",answer:"释义",source:nil,kind:"knowledge")
        let data=try Data(contentsOf:url)
        XCTAssertThrowsError(try store.review(id,grade:0,now:Date()))
        XCTAssertEqual(try Data(contentsOf:url),data)
        try Data("invalid".utf8).write(to:url)
        XCTAssertThrowsError(try PracticeStore(url:url))
    }
    func testSourceRevisionDoesNotDuplicateUnchangedQuestionAndSummaryUsesActualFeedback() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:url)}
        let store=try PracticeStore(url:url)
        var source=StudySource(courseID:"course",kind:"exercise",path:"a.md",anchor:"q1",fingerprint:"old")
        let id=try store.capture(title:"题目",question:"求导",answer:"解答",source:source)
        source.fingerprint="new"
        XCTAssertEqual(try store.capture(title:"题目",question:"求导",answer:"解答",source:source),id)
        try store.update(id){$0.scheduled=true}
        let now=Date(timeIntervalSince1970:2_000_000_000)
        XCTAssertEqual(store.due(now:now).count,1)
        try store.review(id,grade:3,now:now)
        XCTAssertTrue(store.summary(now:now).contains("实际复习次数：1"))
        XCTAssertTrue(try XCTUnwrap(store.items.first).card.due>now)
    }
    func testFlagsAndReviewsPersistWithoutDuplicatingQuestions() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:url)}
        let store=try PracticeStore(url:url)
        let source=StudySource(courseID:"course",kind:"exercise",path:"a.md",anchor:"q1")
        let id=try store.capture(title:"题目",question:"$x^2$",answer:"$2x$",source:source)
        XCTAssertEqual(try store.capture(title:"题目",question:"$x^2$",answer:"$2x$",source:source),id)
        try store.update(id){$0.favorite=true;$0.mistake=true;$0.scheduled=true}
        let before=try XCTUnwrap(store.items.first).card
        try store.review(id,grade:3,now:Date(timeIntervalSince1970:2_000_000_000))
        XCTAssertNotEqual(store.items.first?.card,before)
        try store.undoReview(id)
        XCTAssertEqual(store.items.first?.card,before)
        let restored=try PracticeStore(url:url)
        XCTAssertEqual(restored.items.count,1)
        XCTAssertTrue(try XCTUnwrap(restored.items.first).favorite)
    }
}
