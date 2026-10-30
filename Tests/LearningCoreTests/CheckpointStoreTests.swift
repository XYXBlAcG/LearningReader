import XCTest
@testable import LearningCore

final class CheckpointStoreTests:XCTestCase {
    func testOfflineReopenIsolationRevisionAndIdempotentWrites() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=CheckpointStore(directory:directory)
        let first=CheckpointAttempt(id:UUID(),questionID:"q",signature:"v1",selected:["a"],action:.submit,correct:false,date:1)
        try await store.save(courseID:"math",attempt:first)
        try await store.save(courseID:"math",attempt:first)
        try await store.save(courseID:"other",attempt:.init(id:UUID(),questionID:"q",signature:"v1",selected:["b"],action:.reveal,correct:nil,date:2))
        try await store.draft(courseID:"math",questionID:"q",signature:"v1",selected:["a"])
        let reopened=CheckpointStore(directory:directory)
        let state=try await reopened.state(courseID:"math")
        XCTAssertEqual(state.attempts.count,1)
        XCTAssertFalse(try XCTUnwrap(state.attempts.first?.correct))
        XCTAssertEqual(state.drafts.first?.selected,["a"])
        try await reopened.save(courseID:"math",attempt:.init(id:UUID(),questionID:"q",signature:"v2",selected:["b"],action:.submit,correct:true,date:3))
        let updated=try await reopened.state(courseID:"math")
        XCTAssertEqual(updated.attempts.map(\.signature),["v1","v2"])
        let other=try await reopened.state(courseID:"other")
        XCTAssertEqual(other.attempts.count,1)
        XCTAssertEqual(other.attempts.first?.action,.reveal)
    }
    func testServiceRejectsWrongVersionAndGradesTrustedContent() async throws {
        let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/checkpoint.json")
        let q=try JSONDecoder().decode(CheckpointDefinition.self,from:Data(contentsOf:fixture))
        let engine=try CheckpointEngine()
        let source="# 课\n## 定义\n```checkpoint\n"+String(decoding:try JSONEncoder().encode(q),as:UTF8.self)+"\n```"
        let locations=try engine.catalog([.init(kind:.note,path:"lesson.md",source:source)])
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let service=CheckpointService(courseID:"math",locations:locations,store:CheckpointStore(directory:directory))
        var payload:[String:Any]=["action":"submit","questionID":q.id,"signature":"stale","selected":["one"],"eventID":UUID().uuidString]
        do {_ = try await service.request(JSONDecoder().decode(CheckpointRequest.self,from:JSONSerialization.data(withJSONObject:payload)));XCTFail("stale version accepted")}catch {}
        payload["signature"]=try engine.signature(q)
        let result=try await service.request(JSONDecoder().decode(CheckpointRequest.self,from:JSONSerialization.data(withJSONObject:payload)))
        XCTAssertEqual(result.attempts.first?.correct,true)
    }
}
