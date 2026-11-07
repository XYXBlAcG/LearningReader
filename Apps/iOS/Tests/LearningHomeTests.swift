import XCTest
import LearningCore
@testable import LearningReader

final class LearningHomeTests:XCTestCase {
    func testPreviewRemovesSyntaxWithoutDeletingLiteralHashes() {
        XCTAssertEqual(NotificationPreview.text("# 题目\n\n**求导** [提示](https://example.org)\n\nC# 与 $x^2$"),"题目 求导 提示 C# 与 $x^2$")
    }
    func testJournalRoundTripAndChapterReviewHasOneIdentity() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:url)}
        var store=try LearningJournalStore(url:url)
        let source=LearningLocation(courseKey:"github:1:main:",courseID:"local",kind:"note",path:"chapter.md",title:"章节")
        try store.schedule(source,date:Date(timeIntervalSince1970:200))
        try store.schedule(source,date:Date(timeIntervalSince1970:300))
        store=try LearningJournalStore(url:url)
        XCTAssertEqual(store.archive.chapters.count,1)
        XCTAssertEqual(store.archive.chapters[0].due,Date(timeIntervalSince1970:300))
        try store.complete(store.archive.chapters[0].id,at:Date(timeIntervalSince1970:400))
        XCTAssertTrue(store.archive.chapters.isEmpty)
        XCTAssertEqual(try LearningJournalStore(url:url).archive.events.count,1)
    }
}

extension LearningHomeTests {
    func testClassroomRoundTripRetainsSourceAndDraftSnapshot() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:url)}
        let store=try ClassroomStore(root:url)
        var lesson=ClassroomLesson(title:"中值定理",source:nil)
        lesson.keywords="罗尔定理"
        let attachment=try store.importData(Data("课件原文".utf8),name:"lecture.txt",kind:.text)
        lesson.attachments=[attachment]
        lesson.drafts=[ClassroomDraft(text:"结论 [S1 p1]",sources:[attachment])]
        try store.save(lesson)
        let loaded=try ClassroomStore(root:url)
        XCTAssertEqual(loaded.lessons.first?.drafts.first?.sources.first?.id,attachment.id)
        XCTAssertEqual(try Data(contentsOf:loaded.file(attachment)),Data("课件原文".utf8))
    }
}
