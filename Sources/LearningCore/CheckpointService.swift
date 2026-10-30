import Foundation

public struct CheckpointRequest:Decodable,Sendable {
    public enum Action:String,Decodable,Sendable {case load,draft,submit,reveal}
    public let action:Action
    public let questionID:String?
    public let signature:String?
    public let selected:[String]?
    public let mode:CheckpointMode?
    public let eventID:UUID?
}

public actor CheckpointService {
    private let courseID:String
    private let locations:[CheckpointLocation]
    private let store:CheckpointStore
    public init(courseID:String,locations:[CheckpointLocation],store:CheckpointStore = .shared) {
        self.courseID=courseID;self.locations=locations;self.store=store
    }
    public func request(_ command:CheckpointRequest) async throws -> CheckpointState {
        if command.action != .load {
            guard let item=locations.first(where:{$0.question.id==command.questionID}),
                  let signature=command.signature,let selected=command.selected else {throw ReaderError.course("自测题目已变动，请重新打开课程。")}
            let engine=try CheckpointEngine()
            guard try engine.signature(item.question)==signature else {throw ReaderError.course("自测版本已更新，请重新打开题目。")}
            if !selected.isEmpty {_ = try engine.grade(item.question,selected:selected)}
            switch command.action {
            case .draft:
                guard let mode=command.mode,mode != .feedback else {throw ReaderError.invalidIndex}
                try await store.draft(courseID:courseID,questionID:item.question.id,signature:signature,selected:selected,mode:mode)
            case .submit,.reveal:
                guard let eventID=command.eventID else {throw ReaderError.invalidIndex}
                let result=command.action == .submit ? try engine.grade(item.question,selected:selected).correct : nil
                let attempt=CheckpointAttempt(id:eventID,questionID:item.question.id,signature:signature,selected:selected,action:command.action == .submit ? .submit : .reveal,correct:result,date:Date().timeIntervalSince1970*1000)
                try await store.save(courseID:courseID,attempt:attempt)
            case .load:break
            }
        }
        return try await store.state(courseID:courseID)
    }
}
