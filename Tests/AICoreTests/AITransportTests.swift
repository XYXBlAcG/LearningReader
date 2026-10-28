import XCTest
@testable import AICore

final class AITransportTests: XCTestCase {
    func testURLSessionStreamsFragmentedUTF8AndSendsNativeAuthorization() async throws {
        let capture = AITextCapture()
        try await client().generate(request("complete")) { await capture.set($0) }
        let output = await capture.text
        XCTAssertEqual(output, "数学公式")
    }

    func testConnectionTerminationWithoutCompletionRetainsPartialAnswerAndFails() async throws {
        let capture = AITextCapture()
        do {
            try await client().generate(request("incomplete")) { await capture.set($0) }
            XCTFail("Expected incomplete stream")
        } catch { XCTAssertEqual(error as? AIError, .incomplete) }
        let output = await capture.text
        XCTAssertEqual(output, "数学公式")
    }

    func testHTTPAndContentTypeErrorsAreNotSuccessfulConnections() async {
        for mode in ["unauthorized", "html"] {
            do {
                try await client().generate(request(mode)) { _ in }
                XCTFail("Expected protocol error")
            } catch { XCTAssertEqual(error as? AIError, mode == "html" ? .invalidStream : .service(401)) }
        }
    }

    func testCancellationStopsWaitingForNetwork() async throws {
        let client = client()
        let request = request("slow")
        let task = Task { try await client.generate(request) { _ in } }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || (error as NSError).code == NSURLErrorCancelled) }
    }

    @MainActor
    func testConversationKeepsFollowupTurnsAndStopsPreviousGeneration() async throws {
        let initial = try AIMaterial(title: "Question", text: "selected", document: "首条消息的全文").message()
        let session = AIConversation(title: "Question", profile: request("complete").profile, key: "fixture-key", system: "teach", initial: initial, client: client())
        session.retry()
        for _ in 0..<500 {
            if !session.running { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(session.running)
        XCTAssertNil(session.issue)
        XCTAssertEqual(session.answer, "数学公式")
        XCTAssertEqual(session.record.versions.first?.status,.complete)
        XCTAssertEqual(session.record.versions.count,1)
        session.followUp("再讲一讲")
        XCTAssertEqual(session.messages.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(session.messages[1].text, "数学公式")
        XCTAssertTrue(session.messages[0].text.contains("首条消息的全文"))
        XCTAssertFalse(session.messages[2].text.contains("首条消息的全文"))
        session.stop()
        XCTAssertEqual(session.record.versions.count,2)
        XCTAssertEqual(session.record.versions.first?.answer,"数学公式")
        XCTAssertEqual(session.record.versions.last?.status,.stopped)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(session.running)
        XCTAssertNil(session.issue)
    }

    @MainActor
    func testResumeOldVersionBranchesWithoutDiscardingNewerAnswers() async throws {
        let material=AIMaterial(title:"题目",text:"原题")
        var record=StudyRecord(material:material,initial:try material.message(),system:"教学",action:.explain)
        var first=StudyVersion(input:[],model:"old",service:"s");first.answer="旧答案";first.status = .complete
        var second=StudyVersion(input:[],model:"new",service:"s");second.answer="新答案";second.status = .complete
        record.versions=[first,second]
        let session=AIConversation(title:"题目",profile:request("complete").profile,key:"fixture-key",system:record.system,initial:record.initial,client:client(),restored:record,selectedVersionID:first.id)
        XCTAssertEqual(session.answer,"旧答案")
        session.followUp("接着解释")
        for _ in 0..<500 {if !session.running {break};try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertEqual(session.record.versions.count,3)
        XCTAssertEqual(session.record.versions[1].answer,"新答案")
        XCTAssertEqual(session.messages[1].text,"旧答案")
        XCTAssertEqual(session.answer,"数学公式")
    }

    private func client() -> AIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIHTTPFixture.self]
        return AIClient(session: URLSession(configuration: configuration))
    }
    private func request(_ mode: String) -> AIRequest {
        AIRequest(profile: AIProfile(name: "Test", baseURL: "https://fixture.invalid/\(mode)", model: "fixture"), key: "fixture-key", system: "system", messages: [.init(role: .user, text: "question")])
    }
}

private actor AITextCapture {
    var text = ""
    func set(_ value: String) { text = value }
}

private final class AIHTTPFixture: URLProtocol {
    private var delayed: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        let mode = url.pathComponents[1]
        if mode == "slow" {
            delayed = Task { try? await Task.sleep(nanoseconds: 10_000_000_000) }
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: mode == "unauthorized" ? 401 : 200, httpVersion: nil, headerFields: ["Content-Type": mode == "html" ? "text/html" : "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let content = "data: {\"choices\":[{\"delta\":{\"content\":\"数学公式\"},\"finish_reason\":null}]}\r\n\r\n" + (mode == "incomplete" ? "" : "data: [DONE]\r\n\r\n")
        for byte in content.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { delayed?.cancel() }
}
