import Foundation

public struct SSEParser {
    private var line: [UInt8] = []
    private var data: [String] = []
    private var eventSize = 0
    public init() { }
    public mutating func append(_ bytes: Data) throws -> [String] {
        var result: [String] = []
        for byte in bytes {
            if byte == 10 {
                if line.last == 13 { line.removeLast() }
                guard let text = String(bytes: line, encoding: .utf8) else { throw AIError.invalidStream }
                line.removeAll(keepingCapacity: true)
                if text.isEmpty {
                    if !data.isEmpty { result.append(data.joined(separator: "\n")); data.removeAll(keepingCapacity: true) }
                    eventSize = 0
                } else if text.hasPrefix("data:") {
                    let value = text.dropFirst(5)
                    data.append(String(value.first == " " ? value.dropFirst() : value))
                    eventSize += text.utf8.count
                }
            } else { line.append(byte) }
            guard line.count + eventSize <= 2_000_000 else { throw AIError.invalidStream }
        }
        return result
    }
    public mutating func finish() throws -> [String] { try append(Data("\n\n".utf8)) }
}

public enum AIStreamEvent: Equatable, Sendable { case text(String), completed }

public enum AIStream {
    public static func decode(_ data: String, api: AIProtocol) throws -> [AIStreamEvent] {
        if data == "[DONE]" { return [.completed] }
        guard let object = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else { throw AIError.invalidStream }
        if object["error"] != nil || object["type"] as? String == "error" { throw AIError.generation("服务报告生成失败。请检查模型、权限或图片格式后重试。") }
        switch api {
        case .chatCompletions:
            guard let choices = object["choices"] as? [[String: Any]], let choice = choices.first else { return [] }
            var result: [AIStreamEvent] = []
            if let delta = choice["delta"] as? [String: Any], let text = delta["content"] as? String { result.append(.text(text)) }
            if let reason = choice["finish_reason"] as? String {
                guard reason == "stop" else { throw AIError.incomplete }
                result.append(.completed)
            }
            return result
        case .responses:
            switch object["type"] as? String {
            case "response.output_text.delta": return [.text(object["delta"] as? String ?? "")]
            case "response.refusal.delta": return [.text(object["delta"] as? String ?? "")]
            case "response.completed": return [.completed]
            case "response.failed", "response.incomplete": throw AIError.incomplete
            default: return []
            }
        case .anthropic:
            switch object["type"] as? String {
            case "content_block_delta":
                let delta = object["delta"] as? [String: Any]
                return delta?["type"] as? String == "text_delta" ? [.text(delta?["text"] as? String ?? "")] : []
            case "message_delta":
                if let delta = object["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String, !["end_turn", "stop_sequence"].contains(reason) { throw AIError.incomplete }
                return []
            case "message_stop": return [.completed]
            default: return []
            }
        case .gemini:
            if let feedback = object["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil { throw AIError.generation("服务未接受此问题，请检查输入后重试。") }
            guard let candidates = object["candidates"] as? [[String: Any]], let candidate = candidates.first else { return [] }
            let content = candidate["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            var result: [AIStreamEvent] = parts.filter { $0["thought"] as? Bool != true }.compactMap { ($0["text"] as? String).map(AIStreamEvent.text) }
            if let reason = candidate["finishReason"] as? String {
                guard reason == "STOP" else { throw AIError.incomplete }
                result.append(.completed)
            }
            return result
        }
    }
}
