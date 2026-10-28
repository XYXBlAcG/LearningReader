import Foundation
import CryptoKit

public struct StudySource:Codable,Equatable,Sendable {
    public var courseID:String
    public var kind:String
    public var path:String
    public var anchor:String
    public var fingerprint:String
    public static func hash(_ content:String)->String { SHA256.hash(data:Data(content.utf8)).map{String(format:"%02x",$0)}.joined() }
    public init(courseID:String="",kind:String="",path:String="",anchor:String="",fingerprint:String="") {
        self.courseID=courseID;self.kind=kind;self.path=path;self.anchor=anchor;self.fingerprint=fingerprint
    }
}

public enum StudyStatus:String,Codable,Sendable { case generating,complete,stopped,interrupted }

public struct StudyVersion:Codable,Equatable,Identifiable,Sendable {
    public var id=UUID()
    public var date=Date()
    public var input:[AIMessage]=[]
    public var answer=""
    public var status:StudyStatus = .generating
    public var issue:String?
    public var model:String
    public var service:String
    public init(input:[AIMessage],model:String,service:String) {self.input=input;self.model=model;self.service=service}
    public var transcript:String {
        (input.map{$0.role == .user ? "\n\n---\n\n**追问**\n\n"+$0.text : $0.text}+[answer]).joined(separator:"\n\n")
    }
}

public struct StudyRecord:Codable,Equatable,Identifiable,Sendable {
    public var id=UUID()
    public var title:String
    public var titleEdited=false
    public var createdAt=Date()
    public var updatedAt=Date()
    public var source:StudySource?
    public var question:String
    public var initial:AIMessage
    public var system:String
    public var action:AISelectionAction
    public var versions:[StudyVersion]=[]
    public var position:Double=0
    public var searchText:String {
        let text=question.replacingOccurrences(of:#"!\[[^\]]*\]\([^)]*\)"#,with:"",options:.regularExpression)
        return text+"\n"+versions.map(\.transcript).joined(separator:"\n")
    }
    public var hasAnswer:Bool { versions.contains{!$0.answer.isEmpty} }
    public init(material:AIMaterial,initial:AIMessage,system:String,action:AISelectionAction) {
        question=material.question ?? material.text
        title=material.image == nil ? String(material.text.replacingOccurrences(of:"\n",with:" ").prefix(60)) : material.title
        if title.isEmpty { title=material.title }
        source=material.source;self.initial=initial;self.system=system;self.action=action
    }
}

public struct StudyQuestion:Codable,Identifiable,Sendable {
    public let id:String
    public let label:String
    public var question:String
    public let request:String
    public var answer:String
    public var anchor:String
    public var source:StudySource?
}

public struct StudySummary:Identifiable,Sendable {
    public let id:UUID
    public let title:String
    public let updatedAt:Date
    public let source:StudySource?
    public let questionDigest:String
    public let searchText:String
    public init(id:UUID,title:String,updatedAt:Date,source:StudySource?,questionDigest:String,searchText:String) {
        self.id=id;self.title=title;self.updatedAt=updatedAt;self.source=source;self.questionDigest=questionDigest;self.searchText=searchText
    }
}
