import XCTest
@testable import AICore

final class AITests: XCTestCase {
    func testReasoningSignalsDoNotBecomeAnswerText() throws {
        XCTAssertEqual(try AIStream.decode(#"{"choices":[{"delta":{"reasoning_content":"推理"}}]}"#,api:.chatCompletions),[.thinking])
        XCTAssertEqual(try AIStream.decode(#"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"推理"}}"#,api:.anthropic),[.thinking])
        XCTAssertEqual(try AIStream.decode(#"{"candidates":[{"content":{"parts":[{"thought":true,"text":"推理"},{"text":"答案"}]}}]}"#,api:.gemini),[.thinking,.text("答案")])
    }

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
        let prompt = AIPrompts.system(settings: settings, image: false)
        for word in ["直觉", "严谨过程", "\\frac", "$$", "先修", "符号", "独立", "不"] { XCTAssertTrue(prompt.contains(word), word) }
        settings.profiles = []
        XCTAssertNil(settings.profile(forImage: false))
    }

    func testWholeDocumentSurvivesMaterialAndEveryProtocolWithoutClipping() throws {
        let source = "文件开头\n" + String(repeating: "已知条件。", count: 18000) + "\n参考答案与文件末尾"
        let message = try AIMaterial(title: "课文", text: "选中的问题", document: source).message()
        let quoted = String(message.text.split(separator: "\n", maxSplits: 1)[1])
        let material = try JSONSerialization.jsonObject(with: Data(quoted.utf8)) as! [String: String]
        XCTAssertEqual(material["完整文件"], source)
        for api in AIProtocol.allCases {
            let request = try AIRequest(profile: AIProfile(name: "T", api: api, baseURL: api.defaultURL, model: "m"), key: "k", system: "teach", messages: [message]).urlRequest()
            let body = String(decoding: request.httpBody!, as: UTF8.self)
            XCTAssertTrue(body.contains("文件开头"))
            XCTAssertTrue(body.contains("参考答案与文件末尾"))
            XCTAssertTrue(body.contains("选中的问题"))
            let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let transmitted: String?
            switch api {
            case .chatCompletions: transmitted = (object["messages"] as? [[String: Any]])?.last?["content"] as? String
            case .responses: transmitted = (object["input"] as? [[String: Any]])?.first?["content"] as? String
            case .anthropic:
                let first = (object["messages"] as? [[String: Any]])?.first
                transmitted = (first?["content"] as? [[String: Any]])?.first?["text"] as? String
            case .gemini:
                let first = (object["contents"] as? [[String: Any]])?.first
                transmitted = (first?["parts"] as? [[String: Any]])?.first?["text"] as? String
            }
            XCTAssertEqual(transmitted, message.text)
        }
        XCTAssertThrowsError(try AIMaterial(title: "large", text: "问题", document: String(repeating: "a", count: AIInputBudget.maximumBytes + 1)).message())
    }

    func testCustomTeachingAndFormulaRulesReplaceDefaultsInEveryProtocol() throws {
        var settings = AISettings()
        settings.teachingRules = "只提供启发式问题"
        settings.formulaRules = "使用自定义公式风格"
        settings.actions[0].prompt = "自定义文字任务"
        settings.imagePrompt = "自定义图片任务"
        for image in [false, true] {
            let prompt = AIPrompts.system(settings: settings, image: image)
            XCTAssertTrue(prompt.contains(settings.teachingRules))
            XCTAssertTrue(prompt.contains(settings.formulaRules))
            XCTAssertFalse(prompt.contains("先“直觉”"))
            XCTAssertFalse(prompt.contains("\\frac"))
            XCTAssertTrue(prompt.contains(image ? settings.imagePrompt : settings.actions[0].prompt))
            for api in AIProtocol.allCases {
                let request = try AIRequest(profile: AIProfile(name: "T", api: api, baseURL: api.defaultURL, model: "m"), key: "k", system: prompt, messages: [.init(role: .user, text: "question")]).urlRequest()
                XCTAssertTrue(String(decoding: request.httpBody!, as: UTF8.self).contains(settings.teachingRules))
            }
        }
        settings.teachingRules = ""; settings.formulaRules = ""
        XCTAssertFalse(AIPrompts.system(settings: settings, image: false).contains("\\frac"))
    }

    func testExistingSettingsGainEditableDefaultsWithoutLosingServicesOrPrompts() throws {
        let original = AISettings()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        let profile = AIProfile(name: "saved", model: "model")
        object["profiles"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([profile]))
        object["textProfileID"] = profile.id.uuidString
        object["textPrompt"] = "保留我的提示词"
        object.removeValue(forKey:"actions")
        object.removeValue(forKey: "teachingRules"); object.removeValue(forKey: "formulaRules")
        let restored = try JSONDecoder().decode(AISettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.profiles, [profile])
        XCTAssertEqual(restored.textProfileID, profile.id)
        XCTAssertEqual(restored.actions[0].prompt, "保留我的提示词")
        XCTAssertEqual(restored.teachingRules, AIPrompts.teaching)
        XCTAssertEqual(restored.formulaRules, AIPrompts.formulas)
    }
}
