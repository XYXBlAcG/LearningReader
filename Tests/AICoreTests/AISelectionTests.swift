import XCTest
@testable import AICore

final class AISelectionTests: XCTestCase {
    func testRootDeepSeekURLAndReasoningParameters() throws {
        var profile = AIProfile(name: "DeepSeek", baseURL: "https://api.deepseek.com", model: "configured-model")
        XCTAssertEqual(try profile.endpoint().absoluteString, "https://api.deepseek.com/chat/completions")
        profile.reasoning = AIReasoning(mode: .deepSeek, effort: .max)
        profile.maxOutputTokens=8192
        var body = try payload(profile)
        XCTAssertEqual(body["reasoning_effort"] as? String, "max")
        XCTAssertEqual(body["max_tokens"] as? Int,8192)
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "enabled")
        profile.reasoning = nil
        body = try payload(profile)
        XCTAssertNil(body["reasoning_effort"])
    }

    func testReasoningUsesEachProvidersOwnSchema() throws {
        for api in AIProtocol.allCases {
            var profile = AIProfile(name: "test", api: api, baseURL: api.defaultURL, model: "m")
            profile.reasoning = AIReasoning(mode: .effort, effort: .high)
            let body = try payload(profile)
            switch api {
            case .chatCompletions: XCTAssertEqual(body["reasoning_effort"] as? String,"high")
            case .responses: XCTAssertEqual((body["reasoning"] as? [String:String])?["effort"],"high")
            case .anthropic: XCTAssertEqual((body["output_config"] as? [String:String])?["effort"],"high")
            case .gemini:
                let generation = body["generationConfig"] as? [String:Any]
                XCTAssertEqual((generation?["thinkingConfig"] as? [String:String])?["thinkingLevel"],"HIGH")
            }
        }
        var profile = AIProfile(name:"Claude",api:.anthropic,baseURL:AIProtocol.anthropic.defaultURL,model:"m")
        profile.reasoning = AIReasoning(mode:.budget, budget:4096)
        XCTAssertEqual((try payload(profile)["thinking"] as? [String:Any])?["budget_tokens"] as? Int,4096)
        profile.maxOutputTokens = 2048
        XCTAssertThrowsError(try payload(profile))
    }

    func testActionSettingsKeepOldPromptAndContextPreferences() throws {
        var settings = AISettings()
        settings.actions = [AISelectionAction(title:"出一道变式",prompt:"只出题",enabled:true)]
        settings.askForContext = false; settings.includeDocumentByDefault = false
        let restored = try JSONDecoder().decode(AISettings.self,from:JSONEncoder().encode(settings))
        XCTAssertEqual(restored,settings)
        var object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as! [String:Any]
        object.removeValue(forKey:"actions"); object["textPrompt"] = "我的旧提示词"
        let migrated = try JSONDecoder().decode(AISettings.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(migrated.actions[0].prompt,"我的旧提示词")
        XCTAssertEqual(migrated.actions[0].title,"讲一讲")
    }

    func testSelectionOnlyOmitsDocumentFromRequest() throws {
        let material = AIMaterial(title:"title",text:"问题",document:"全文专有条件")
        XCTAssertFalse(try material.message(includeDocument:false).text.contains("全文专有条件"))
        XCTAssertTrue(try material.message(includeDocument:true).text.contains("全文专有条件"))
    }

    @MainActor
    func testInvocationShowsPreparationChoiceAndVisibleFailure() async throws {
        let run = AIInvocation(action:.explain,askForContext:true,includeDocument:true)
        run.prepare { AIMaterial(title:"file",text:"问题",document:"全文") }
        for _ in 0..<50 { if !run.preparing { break }; try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertTrue(run.needsContextChoice)
        XCTAssertNotNil(run.material)
        let failed = AIInvocation(action:.explain,askForContext:false,includeDocument:false)
        failed.prepare { throw AISelectionError.noSelection }
        for _ in 0..<50 { if !failed.preparing { break }; try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertNotNil(failed.issue)
        let timeout = AIInvocation(action:.explain,askForContext:false,includeDocument:false)
        timeout.prepare(timeoutNanoseconds:5_000_000) { try await Task.sleep(nanoseconds:200_000_000); return AIMaterial(title:"file",text:"late") }
        try await Task.sleep(nanoseconds:30_000_000)
        XCTAssertNotNil(timeout.issue)
        XCTAssertNil(timeout.material)
    }

    func testOptionalReasoningAndOutputSettingsMigrateAndCompose() throws {
        let old=Data(#"{"id":"B5A87E9B-305D-4E48-9241-7B47B4D8EA01","name":"saved","api":"chatCompletions","baseURL":"https://api.deepseek.com","model":"m","supportsImages":false}"#.utf8)
        let restored=try JSONDecoder().decode(AIProfile.self,from:old)
        XCTAssertNil(restored.reasoning)
        XCTAssertNil(restored.maxOutputTokens)
        var profile=AIProfile(name:"Gemini",api:.gemini,baseURL:AIProtocol.gemini.defaultURL,model:"m")
        profile.reasoning=AIReasoning(mode:.budget,budget:2048)
        profile.maxOutputTokens=8192
        let config=try payload(profile)["generationConfig"] as! [String:Any]
        XCTAssertEqual(config["maxOutputTokens"] as? Int,8192)
        XCTAssertEqual((config["thinkingConfig"] as? [String:Int])?["thinkingBudget"],2048)
        XCTAssertEqual(try JSONDecoder().decode(AIProfile.self,from:JSONEncoder().encode(profile)),profile)
    }

    @MainActor
    func testContextDefaultsAndCancellationDoNotLeakLateMaterial() async throws {
        let run=AIInvocation(action:.variation,askForContext:false,includeDocument:false)
        run.prepare { AIMaterial(title:"file",text:"问题",document:"全文") }
        for _ in 0..<100 { if !run.preparing { break }; try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertFalse(run.needsContextChoice)
        XCTAssertFalse(run.includeDocument)
        XCTAssertEqual(run.action.title,"出一道变式")
        let cancelled=AIInvocation(action:.explain,askForContext:true,includeDocument:true)
        cancelled.prepare { try? await Task.sleep(nanoseconds:10_000_000);return AIMaterial(title:"file",text:"late") }
        cancelled.cancel()
        try await Task.sleep(nanoseconds:20_000_000)
        XCTAssertNil(cancelled.material)
        XCTAssertNil(cancelled.conversation)
    }

    private func payload(_ profile: AIProfile) throws -> [String:Any] {
        let request = try AIRequest(profile:profile,key:"fixture",system:"teach",messages:[.init(role:.user,text:"question")]).urlRequest()
        return try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
    }
}
