import Foundation

public enum CheckpointAction:String,Codable,Sendable { case submit,reveal }
public enum CheckpointMode:String,Codable,Sendable { case editing,feedback,skipped }

public struct CheckpointAttempt:Codable,Sendable {
    public let id:UUID
    public let questionID:String
    public let signature:String
    public let selected:[String]
    public let action:CheckpointAction
    public let correct:Bool?
    public let date:Double
    public init(id:UUID,questionID:String,signature:String,selected:[String],action:CheckpointAction,correct:Bool?,date:Double) {
        self.id=id;self.questionID=questionID;self.signature=signature;self.selected=selected;self.action=action;self.correct=correct;self.date=date
    }
}

public struct CheckpointDraft:Codable,Sendable {
    public let questionID:String
    public let signature:String
    public let selected:[String]
    public let mode:CheckpointMode
}

public struct CheckpointState:Codable,Sendable {
    public var attempts:[CheckpointAttempt]=[]
    public var drafts:[CheckpointDraft]=[]
    public init() {}
}

public actor CheckpointStore {
    public static let shared=CheckpointStore(directory:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LearningReader/Checkpoints"))
    private let file:URL
    public init(directory:URL) {file=directory.appendingPathComponent("attempts.json")}
    public func state(courseID:String) throws -> CheckpointState {try read().courses[courseID] ?? .init()}
    public func save(courseID:String,attempt:CheckpointAttempt) throws {
        var ledger=try read(),state=ledger.courses[courseID] ?? .init()
        if state.attempts.contains(where:{$0.id==attempt.id}) {return}
        state.attempts.append(attempt)
        state.drafts.removeAll{$0.questionID==attempt.questionID&&$0.signature==attempt.signature}
        state.drafts.append(.init(questionID:attempt.questionID,signature:attempt.signature,selected:attempt.selected,mode:.feedback))
        ledger.courses[courseID]=state
        try write(ledger)
    }
    public func draft(courseID:String,questionID:String,signature:String,selected:[String],mode:CheckpointMode = .editing) throws {
        var ledger=try read(),state=ledger.courses[courseID] ?? .init()
        state.drafts.removeAll{$0.questionID==questionID&&$0.signature==signature}
        state.drafts.append(.init(questionID:questionID,signature:signature,selected:selected,mode:mode))
        ledger.courses[courseID]=state
        try write(ledger)
    }
    private struct Ledger:Codable {
        let version:Int
        var courses:[String:CheckpointState]
    }
    private func read() throws -> Ledger {
        guard FileManager.default.fileExists(atPath:file.path) else {return .init(version:1,courses:[:])}
        let ledger=try JSONDecoder().decode(Ledger.self,from:Data(contentsOf:file))
        guard ledger.version==1 else {throw CocoaError(.fileReadCorruptFile)}
        return ledger
    }
    private func write(_ ledger:Ledger) throws {
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(ledger).write(to:file,options:.atomic)
    }
}
