import Foundation

public struct AISelectionAction: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var prompt: String
    public var enabled: Bool
    public init(id: UUID = UUID(), title: String = "", prompt: String = "", enabled: Bool = true) { self.id=id; self.title=title; self.prompt=prompt; self.enabled=enabled }
    public static let explainID = UUID(uuidString:"B5A87E9B-305D-4E48-9241-7B47B4D8EA01")!
    public static var explain: Self { .init(id:explainID,title:"讲一讲",prompt:AIPrompts.text) }
    public static var variation: Self { .init(title:"出一道变式",prompt:"结合提供的材料，为所选题目出一道条件完整、方法相关的变式；先只给题目，暂不展示答案。") }
}

public enum AISelectionError: LocalizedError {
    case noSelection, documentChanged, bridgeUnavailable, timeout, invalidPayload
    public var errorDescription: String? {
        switch self {
        case .noSelection: return "没有取得选中文字，请重新选中后再试。（选区读取）"
        case .documentChanged: return "原文已切换，请在当前页面重新选择。（文档校验）"
        case .bridgeUnavailable: return "阅读器尚未准备就绪，请稍后重试。（阅读器桥接）"
        case .timeout: return "读取选区超时，请重试或刷新页面。（选区读取）"
        case .invalidPayload: return "阅读器返回的材料格式无效。（材料解码）"
        }
    }
}
