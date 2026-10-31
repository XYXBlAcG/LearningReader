import XCTest
import AICore
import StudyLibrary
@testable import LearningReader

@MainActor
final class StudyOpeningTests: XCTestCase {
    func testSavedSummaryLoadsCompleteRecordWithoutAIConfiguration() throws {
        let store=try StudyStore(inMemory:true)
        var record=StudyRecord(material:.init(title:"题目",text:"求导"),initial:.init(role:.user,text:"题目与上下文"),system:"教学",action:.explain)
        var version=StudyVersion(input:[],model:"offline",service:"saved")
        version.answer="导数为 $2x$。";version.status = .complete;record.versions=[version]
        try store.upsert(record)
        let workspace=StudyWorkspace(store:store)
        let id=try XCTUnwrap(workspace.records.first?.id)
        let opened=try workspace.openRecord(id)
        XCTAssertEqual(opened.question,record.question)
        XCTAssertEqual(opened.versions.last?.answer,version.answer)
        XCTAssertThrowsError(try workspace.openRecord(UUID()))
    }
}
