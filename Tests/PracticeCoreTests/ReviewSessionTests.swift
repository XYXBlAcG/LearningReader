import XCTest
@testable import PracticeCore

final class ReviewSessionTests: XCTestCase {
    func testSessionPersistsFixedQueueAndUndoRestoresPosition() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try PracticeStore(url: url)
        let first = try store.capture(title: "一", question: "一", answer: "答", source: nil)
        let second = try store.capture(title: "二", question: "二", answer: "答", source: nil)
        try store.startSession(ids: [first, second])
        try store.review(first, grade: 3, now: Date(), evidence: .init(hintLevel: 2))
        XCTAssertEqual(store.session?.current, second)
        let restored = try PracticeStore(url: url)
        XCTAssertEqual(restored.session?.current, second)
        XCTAssertEqual(restored.items[0].reviews.last?.evidence?.hintLevel, 2)
        try restored.undoReview(first)
        XCTAssertEqual(restored.session?.current, first)
        XCTAssertTrue(restored.items[0].reviews.isEmpty)
    }
}
