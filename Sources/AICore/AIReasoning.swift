import Foundation

public enum AIReasoningEffort: String, Codable, CaseIterable, Sendable {
    case none, minimal, low, medium, high, xhigh, max
    public var title: String {
        switch self {
        case .none: return "关闭"
        case .minimal: return "最低"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        case .xhigh: return "很高"
        case .max: return "最高"
        }
    }
}

public enum AIReasoningMode: String, Codable, CaseIterable, Sendable {
    case effort, deepSeek, adaptive, budget
    public var title: String {
        switch self {
        case .effort: return "推理强度"
        case .deepSeek: return "DeepSeek 思考模式"
        case .adaptive: return "Claude 自适应思考"
        case .budget: return "思考 Token 预算"
        }
    }
    public static func available(for api: AIProtocol) -> [Self] {
        switch api {
        case .chatCompletions: return [.effort,.deepSeek]
        case .responses: return [.effort]
        case .anthropic: return [.effort,.adaptive,.budget]
        case .gemini: return [.effort,.budget]
        }
    }
}

public struct AIReasoning: Codable, Equatable, Sendable {
    public var mode: AIReasoningMode
    public var effort: AIReasoningEffort
    public var budget: Int
    public init(mode: AIReasoningMode = .effort, effort: AIReasoningEffort = .medium, budget: Int = 4096) { self.mode=mode; self.effort=effort; self.budget=budget }
    public func efforts(for api: AIProtocol) -> [AIReasoningEffort] {
        if mode == .deepSeek { return [.none,.low,.high,.max] }
        switch api {
        case .chatCompletions,.responses: return AIReasoningEffort.allCases
        case .anthropic: return [.low,.medium,.high,.xhigh,.max]
        case .gemini: return [.minimal,.low,.medium,.high]
        }
    }
    public func apply(to body: inout [String:Any], api: AIProtocol) throws {
        guard AIReasoningMode.available(for:api).contains(mode) else { throw AIError.generation("当前接口不支持所选推理参数模式。") }
        if mode != .budget, !efforts(for:api).contains(effort) { throw AIError.generation("当前接口不支持所选推理强度。") }
        if mode == .deepSeek {
            body["thinking"] = ["type":effort == .none ? "disabled" : "enabled"]
            if effort != .none { body["reasoning_effort"] = effort.rawValue }
            return
        }
        switch api {
        case .chatCompletions: body["reasoning_effort"]=effort.rawValue
        case .responses: body["reasoning"]=["effort":effort.rawValue]
        case .anthropic:
            if mode == .budget {
                guard budget >= 1024, budget < (body["max_tokens"] as? Int ?? 0) else { throw AIError.generation("Claude 思考预算须至少 1024，且小于最大输出 Token 数。") }
                body["thinking"]=["type":"enabled","budget_tokens":budget]
            } else {
                body["output_config"]=["effort":effort.rawValue]
                if mode == .adaptive { body["thinking"]=["type":"adaptive"] }
            }
        case .gemini:
            if mode == .budget, budget < -1 { throw AIError.generation("思考预算须为非负整数，或用 -1 表示动态预算。") }
            var config=body["generationConfig"] as? [String:Any] ?? [:]
            config["thinkingConfig"] = mode == .budget ? ["thinkingBudget":budget] : ["thinkingLevel":effort.rawValue.uppercased()]
            body["generationConfig"]=config
        }
    }
}
