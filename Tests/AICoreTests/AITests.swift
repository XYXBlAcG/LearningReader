import XCTest
@testable import AICore

final class AITests: XCTestCase {
    func testEndpointsPreserveVersionAndGatewayPrefix() throws {
        for api in AIProtocol.allCases {
            var profile = AIProfile(name: "Test", api: api, baseURL: "https://example.org/gateway/\(api == .gemini ? "v1beta" : "v1")/", model: "test-model")
            let url = try profile.endpoint()
            XCTAssertTrue(url.path.hasPrefix("/gateway/"))
            profile.baseURL = url.absoluteString
            XCTAssertEqual(try profile.endpoint(), url)
        }
        var profile = AIProfile(name: "Test", baseURL: "http://example.org", model: "m")
        XCTAssertThrowsError(try profile.endpoint())
        profile.baseURL = "https://user:key@example.org/v1"
        XCTAssertThrowsError(try profile.endpoint())
    }

    func testEveryAdapterIncludesImagesAndKeepsSecretsInHeaders() throws {
        for api in AIProtocol.allCases {
            let profile = AIProfile(name: "Test", api: api, baseURL: api.defaultURL, model: "test-model", supportsImages: true)
            let request = try AIRequest(profile: profile, key: "secret-key", system: "teach", messages: [.init(role: .user, text: "question", image: .init(data: Data([1, 2, 3]), mimeType: "image/jpeg"))]).urlRequest()
            let body = String(decoding: request.httpBody!, as: UTF8.self)
            XCTAssertTrue(body.contains("AQID"))
            XCTAssertFalse(body.contains("secret-key"))
            XCTAssertFalse(request.url!.absoluteString.contains("secret-key"))
            XCTAssertTrue(body.contains("teach"))
        }
        let profile = AIProfile(name: "Text", model: "text")
        XCTAssertThrowsError(try AIRequest(profile: profile, key: "k", system: "s", messages: [.init(role: .user, text: "x", image: .init(data: Data([1]), mimeType: "image/jpeg"))]).urlRequest())
    }

    func testSSEHandlesCRLFSplitUTF8AndMultilineEvents() throws {
        var parser = SSEParser()
        let bytes = Data("event: test\r\ndata: {\"text\":\"数学\"}\r\ndata: second\r\n\r\n".utf8)
        var events: [String] = []
        for byte in bytes { events += try parser.append(Data([byte])) }
        XCTAssertEqual(events, ["{\"text\":\"数学\"}\nsecond"])
        XCTAssertTrue(try parser.finish().isEmpty)
    }

    func testAllStreamFormatsNormalizeTextAndCompletion() throws {
        let samples: [(AIProtocol, String, String)] = [
            (.chatCompletions, #"{"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}"#, #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#),
            (.responses, #"{"type":"response.output_text.delta","delta":"你好"}"#, #"{"type":"response.completed"}"#),
            (.anthropic, #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}"#, #"{"type":"message_stop"}"#),
            (.gemini, #"{"candidates":[{"content":{"parts":[{"text":"你好"}]}}]}"#, #"{"candidates":[{"finishReason":"STOP"}]}"#)
        ]
        for (api, text, done) in samples {
            XCTAssertEqual(try AIStream.decode(text, api: api), [.text("你好")])
            XCTAssertEqual(try AIStream.decode(done, api: api), [.completed])
        }
        XCTAssertThrowsError(try AIStream.decode(#"{"error":{"message":"bad"}}"#, api: .chatCompletions))
        XCTAssertThrowsError(try AIStream.decode(#"{"choices":[{"delta":{},"finish_reason":"length"}]}"#, api: .chatCompletions))
    }

    func testSettingsPersistenceAndPromptContract() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AISettingsStore(url: directory.appendingPathComponent("settings.json"))
        var settings = AISettings()
        let profile = AIProfile(name: "Vision", model: "m", supportsImages: true)
        settings.profiles = [profile]; settings.textProfileID = profile.id; settings.imageProfileID = profile.id
        try store.save(settings)
        XCTAssertEqual(try store.load(), settings)
        let prompt = AIPrompts.system(custom: "用中文讲解", image: false)
        for word in ["直觉", "严谨过程", "\\frac", "$$", "先修", "符号", "独立", "不"] { XCTAssertTrue(prompt.contains(word), word) }
        settings.profiles = []
        XCTAssertNil(settings.profile(forImage: false))
    }
}
