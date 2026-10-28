import Foundation

public enum AIProtocol: String, Codable, CaseIterable, Sendable {
    case chatCompletions, responses, anthropic, gemini
    public var title: String {
        switch self {
        case .chatCompletions: return "OpenAI 兼容 · Chat Completions"
        case .responses: return "OpenAI · Responses"
        case .anthropic: return "Claude · Messages"
        case .gemini: return "Gemini · Generate Content"
        }
    }
    public var defaultURL: String {
        switch self {
        case .chatCompletions, .responses: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        }
    }
}

public struct AIProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var api: AIProtocol
    public var baseURL: String
    public var model: String
    public var supportsImages: Bool
    public var reasoning: AIReasoning?
    public var maxOutputTokens: Int?
    public var modelID: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    public init(id: UUID = UUID(), name: String = "", api: AIProtocol = .chatCompletions, baseURL: String = AIProtocol.chatCompletions.defaultURL, model: String = "", supportsImages: Bool = false) {
        self.id = id; self.name = name; self.api = api; self.baseURL = baseURL; self.model = model; self.supportsImages = supportsImages
    }
    public func endpoint() throws -> URL {
        guard !modelID.isEmpty, modelID.range(of: "^[A-Za-z0-9_.:/-]+$", options: .regularExpression) != nil,
              var parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil else { throw AIError.configuration }
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix: String
        switch api {
        case .chatCompletions: suffix = "chat/completions"
        case .responses: suffix = "responses"
        case .anthropic: suffix = "messages"
        case .gemini:
            let name = modelID.hasPrefix("models/") ? String(modelID.dropFirst(7)) : modelID
            guard !name.contains("/"), !name.contains(":") else { throw AIError.configuration }
            suffix = "models/\(name):streamGenerateContent"
        }
        if path != suffix && !path.hasSuffix("/" + suffix) {
            path = path.isEmpty ? suffix : path + "/" + suffix
        }
        parts.path = "/" + path
        guard parts.queryItems == nil || (api == .gemini && parts.queryItems == [URLQueryItem(name: "alt", value: "sse")]) else { throw AIError.configuration }
        if api == .gemini { parts.queryItems = [.init(name: "alt", value: "sse")] }
        guard let url = parts.url else { throw AIError.configuration }
        return url
    }
}

public struct AISettings: Codable, Equatable, Sendable {
    public var profiles: [AIProfile] = []
    public var textProfileID: UUID?
    public var imageProfileID: UUID?
    public var actions: [AISelectionAction] = [.explain]
    public var autoSaveExplanations = true
    public var askForContext = true
    public var includeDocumentByDefault = true
    public var imagePrompt = AIPrompts.image
    public var teachingRules = AIPrompts.teaching
    public var formulaRules = AIPrompts.formulas
    public init() { }
    private enum CodingKeys: String, CodingKey {
        case autoSaveExplanations, profiles, textProfileID, imageProfileID, textPrompt, actions, askForContext, includeDocumentByDefault, imagePrompt, teachingRules, formulaRules
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try values.decode([AIProfile].self, forKey: .profiles)
        textProfileID = try values.decodeIfPresent(UUID.self, forKey: .textProfileID)
        imageProfileID = try values.decodeIfPresent(UUID.self, forKey: .imageProfileID)
        if let saved = try values.decodeIfPresent([AISelectionAction].self,forKey:.actions) { actions=saved }
        else { var initial=AISelectionAction.explain; initial.prompt=try values.decodeIfPresent(String.self,forKey:.textPrompt) ?? AIPrompts.text; actions=[initial] }
        autoSaveExplanations=try values.decodeIfPresent(Bool.self,forKey:.autoSaveExplanations) ?? true
        askForContext=try values.decodeIfPresent(Bool.self,forKey:.askForContext) ?? true
        includeDocumentByDefault=try values.decodeIfPresent(Bool.self,forKey:.includeDocumentByDefault) ?? true
        imagePrompt = try values.decode(String.self, forKey: .imagePrompt)
        teachingRules = try values.decodeIfPresent(String.self, forKey: .teachingRules) ?? AIPrompts.teaching
        formulaRules = try values.decodeIfPresent(String.self, forKey: .formulaRules) ?? AIPrompts.formulas
    }
    public func encode(to encoder: Encoder) throws {
        var values=encoder.container(keyedBy:CodingKeys.self)
        try values.encode(autoSaveExplanations,forKey:.autoSaveExplanations)
        try values.encode(profiles,forKey:.profiles)
        try values.encodeIfPresent(textProfileID,forKey:.textProfileID)
        try values.encodeIfPresent(imageProfileID,forKey:.imageProfileID)
        try values.encode(actions,forKey:.actions)
        try values.encode(askForContext,forKey:.askForContext)
        try values.encode(includeDocumentByDefault,forKey:.includeDocumentByDefault)
        try values.encode(imagePrompt,forKey:.imagePrompt)
        try values.encode(teachingRules,forKey:.teachingRules)
        try values.encode(formulaRules,forKey:.formulaRules)
    }
    public func profile(forImage image: Bool) -> AIProfile? {
        let id = image ? imageProfileID ?? textProfileID : textProfileID
        return profiles.first { $0.id == id && (!image || $0.supportsImages) }
    }
}

public struct AISettingsStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> AISettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return AISettings() }
        return try JSONDecoder().decode(AISettings.self, from: Data(contentsOf: url))
    }
    public func save(_ settings: AISettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: url, options: .atomic)
    }
}

public enum AIError: LocalizedError, Equatable {
    case configuration, missingKey, imageUnsupported, invalidStream, incomplete, empty, contextLimit, outputLimit, service(Int), generation(String)
    public var errorDescription: String? {
        switch self {
        case .configuration: return "请检查接口类型、HTTPS API 地址和模型 ID。地址不能包含密钥、账号或额外查询参数。"
        case .missingKey: return "请在设置中填写 API Key。"
        case .imageUnsupported: return "请配置支持图片的模型，并选择为图片服务。"
        case .invalidStream: return "服务返回的数据不符合所选接口协议。"
        case .incomplete: return "回答未完整结束，可能达到输出上限或连接中断。可重试或继续追问。"
        case .empty: return "服务没有返回可显示的文字。请检查模型及接口类型。"
        case .contextLimit: return "文件与对话超过客户端单次输入上限（\(AIInputBudget.maximumBytes) 字节或 \(AIInputBudget.maximumMessages) 条消息），未截断内容。请换用较小的文件或开始新问题。"
        case .outputLimit: return "回答超过客户端显示上限，请围绕当前问题分步追问。"
        case .service(let code):
            if code == 401 || code == 403 { return "API 授权失败（HTTP \(code)），请检查 Key 和模型权限。" }
            if code == 429 { return "API 请求受限或额度不足（HTTP 429），请稍后重试或检查账户。" }
            return "API 请求失败（HTTP \(code)）。请检查地址、模型、服务输入长度限制及图片支持情况。"
        case .generation(let reason): return reason
        }
    }
}
