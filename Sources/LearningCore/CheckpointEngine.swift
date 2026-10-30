import Foundation
import JavaScriptCore

public struct CheckpointLocation:Codable,Sendable {
    public let kind:DocumentKind
    public let path:String
    public let question:CheckpointDefinition
}

public struct CheckpointGrade:Codable,Sendable {
    public let correct:Bool
    public let missing:[String]
    public let extra:[String]
}

public final class CheckpointEngine {
    private let context:JSContext
    public init() throws {
        guard let context=JSContext() else {throw ReaderError.invalidIndex}
        self.context=context
        context.evaluateScript(try String(contentsOf:ReaderAssets.reader.appendingPathComponent("checkpoint-core.js"),encoding:.utf8))
        guard context.exception==nil else {throw ReaderError.course(context.exception?.toString() ?? "自测引擎初始化失败")}
    }
    public func catalog(_ documents:[CourseDocument]) throws -> [CheckpointLocation] {
        try call(["action":"catalog","documents":try JSONSerialization.jsonObject(with:JSONEncoder().encode(documents))])
    }
    public func grade(_ question:CheckpointDefinition,selected:[String]) throws -> CheckpointGrade {
        try call(["action":"grade","question":try JSONSerialization.jsonObject(with:JSONEncoder().encode(question)),"selected":selected])
    }
    public func signature(_ question:CheckpointDefinition) throws -> String {
        try call(["action":"signature","question":try JSONSerialization.jsonObject(with:JSONEncoder().encode(question))])
    }
    private func call<T:Decodable>(_ request:[String:Any]) throws -> T {
        context.exception=nil
        let input=String(decoding:try JSONSerialization.data(withJSONObject:request),as:UTF8.self)
        let output=context.objectForKeyedSubscript("ReaderCheckpoints")?.forProperty("requestJSON")?.call(withArguments:[input])?.toString()
        if let error=context.exception {throw ReaderError.course(error.toString() ?? "自测数据无效")}
        guard let output else {throw ReaderError.invalidIndex}
        return try JSONDecoder().decode(T.self,from:Data(output.utf8))
    }
}
