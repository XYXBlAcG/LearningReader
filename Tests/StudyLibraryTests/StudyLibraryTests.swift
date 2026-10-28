import XCTest
import AICore
@testable import StudyLibrary

@MainActor
final class StudyLibraryTests:XCTestCase {
    func testSaveRenameDeleteUndoAndLateWrites() throws {
        guard #available(macOS 14,iOS 17,*) else {throw XCTSkip("SwiftData requires macOS 14 or iOS 17")}
        let store=try StudyStore(inMemory:true)
        var record=StudyRecord(material:.init(title:"题",text:"问题"),initial:.init(role:.user,text:"上下文"),system:"教学",action:.explain)
        var version=StudyVersion(input:[],model:"m",service:"test");version.answer="答案 $x^2$";version.status = .complete
        record.versions=[version]
        XCTAssertEqual(try store.summaries().count,0)
        try store.upsert(record)
        XCTAssertEqual(try store.summaries().first?.questionDigest,StudySource.hash(record.question))
        try store.position(record.id,value:123)
        try store.rename(record.id,title:"自己的标题")
        try store.upsert(record)
        XCTAssertEqual(try store.records().first?.title,"自己的标题")
        XCTAssertEqual(try store.records().first?.position,123)
        try store.delete([record.id])
        try store.upsert(record)
        XCTAssertTrue(try store.records().isEmpty)
        try store.undo()
        XCTAssertEqual(try store.records().first?.title,"自己的标题")
        let backup=try store.backup()
        let other=try StudyStore(inMemory:true)
        try other.restore(backup)
        try other.restore(backup)
        let packaged=try StudyArchive.package(record,version:version)
        let fromPackage=try StudyStore(inMemory:true)
        try fromPackage.restore(packaged)
        XCTAssertEqual(try fromPackage.records().first?.question,record.question)
        XCTAssertEqual(try other.records().count,1)
        XCTAssertThrowsError(try other.restore(Data("broken".utf8)))
        XCTAssertEqual(try other.records().count,1)
    }
    func testVersionDeletionRejectsLateCallbacksAndKeepsOrder() throws {
        guard #available(macOS 14,iOS 17,*) else {throw XCTSkip("SwiftData requires macOS 14 or iOS 17")}
        let store=try StudyStore(inMemory:true)
        var record=StudyRecord(material:.init(title:"题",text:"问题"),initial:.init(role:.user,text:"上下文"),system:"教学",action:.explain)
        var first=StudyVersion(input:[],model:"first",service:"s");first.answer="第一个答案";first.status = .complete
        var second=StudyVersion(input:[],model:"second",service:"s");second.answer="第二个答案";second.status = .complete;second.date=first.date
        record.versions=[first,second]
        try store.upsert(record)
        XCTAssertEqual(try store.records().first?.versions.map(\.model),["first","second"])
        try store.deleteVersion(recordID:record.id,versionID:second.id)
        try store.upsert(record)
        XCTAssertEqual(try store.records().first?.versions.map(\.model),["first"])
    }
    func testDiskReopenPreservesImagesAndMarksUnfinishedAnswer() throws {
        guard #available(macOS 14,iOS 17,*) else {throw XCTSkip("SwiftData requires macOS 14 or iOS 17")}
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        var record=StudyRecord(material:.init(title:"图",text:"读图",image:.init(data:Data([1,2,3]),mimeType:"image/jpeg")),initial:.init(role:.user,text:"问题",image:.init(data:Data([1,2,3]),mimeType:"image/jpeg")),system:"系统",action:.explain)
        var version=StudyVersion(input:[],model:"m",service:"test");version.answer="部分回答";record.versions=[version]
        do { let store=try StudyStore(directory:directory);try store.upsert(record) }
        let reopened=try StudyStore(directory:directory)
        let restored=try XCTUnwrap(reopened.records().first)
        XCTAssertEqual(restored.initial.image?.data,Data([1,2,3]))
        XCTAssertEqual(restored.versions.last?.status,.interrupted)
        XCTAssertEqual(restored.initial.text,"问题")
    }
}
