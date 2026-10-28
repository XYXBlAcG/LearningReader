import Foundation
import SwiftData
import AICore

@available(macOS 14,iOS 17,*)
@Model
final class StoredStudy {
    @Attribute(.unique) var id:UUID
    var title:String
    var titleEdited:Bool
    var createdAt:Date
    var updatedAt:Date
    @Attribute(.externalStorage) var questionData:Data
    var questionDigest:String
    var searchText:String
    var question:String { String(decoding:questionData,as:UTF8.self) }
    @Attribute(.externalStorage) var initialData:Data
    var initialText:String {String(decoding:initialData,as:UTF8.self)}
    var initialMime:String?
    @Attribute(.externalStorage) var initialImage:Data?
    var system:String
    var source:Data?
    var action:Data
    var position:Double
    @Relationship(deleteRule:.cascade) var versions:[StoredStudyVersion]
    init(_ record:StudyRecord) throws {
        id=record.id;title=record.title;titleEdited=record.titleEdited;createdAt=record.createdAt;updatedAt=record.updatedAt
        questionData=Data(record.question.utf8);questionDigest=StudySource.hash(record.question);searchText=record.searchText
        initialData=Data(record.initial.text.utf8);initialImage=record.initial.image?.data;initialMime=record.initial.image?.mimeType
        system=record.system;source=try record.source.map{try JSONEncoder().encode($0)};action=try JSONEncoder().encode(record.action)
        position=record.position;versions=record.versions.enumerated().map{StoredStudyVersion($0.element,order:$0.offset)}
    }
    var record:StudyRecord {
        get throws {
            let image=initialImage.map{AIImage(data:$0,mimeType:initialMime ?? "image/jpeg")}
            let origin=try source.map{try JSONDecoder().decode(StudySource.self,from:$0)}
            let task=try JSONDecoder().decode(AISelectionAction.self,from:action)
            var result=StudyRecord(material:.init(title:title,text:question,source:origin),initial:.init(role:.user,text:initialText,image:image),system:system,action:task)
            result.id=id;result.title=title;result.titleEdited=titleEdited;result.createdAt=createdAt;result.updatedAt=updatedAt
            result.position=position;result.versions=try versions.sorted{$0.order<$1.order}.map{try $0.version}
            return result
        }
    }
}

@available(macOS 14,iOS 17,*)
@Model
final class StoredStudyVersion {
    var order:Int
    var id:UUID
    var date:Date
    var answer:String
    var status:String
    var issue:String?
    var model:String
    var service:String
    @Relationship(deleteRule:.cascade) var input:[StoredStudyMessage]
    init(_ version:StudyVersion,order:Int) {
        self.order=order
        id=version.id;date=version.date;answer=version.answer;status=version.status.rawValue;issue=version.issue;model=version.model;service=version.service
        input=version.input.enumerated().map{StoredStudyMessage($0.element,order:$0.offset)}
    }
    var version:StudyVersion {
        get throws {
            guard let state=StudyStatus(rawValue:status) else {throw CocoaError(.fileReadCorruptFile)}
            var result=StudyVersion(input:try input.sorted{$0.order<$1.order}.map{try $0.message},model:model,service:service)
            result.id=id;result.date=date;result.answer=answer;result.status=state;result.issue=issue
            return result
        }
    }
}

@available(macOS 14,iOS 17,*)
@Model
final class StoredStudyMessage {
    var order:Int
    var role:String
    var text:String
    var mime:String?
    @Attribute(.externalStorage) var image:Data?
    init(_ message:AIMessage,order:Int) { self.order=order;role=message.role.rawValue;text=message.text;mime=message.image?.mimeType;image=message.image?.data }
    var message:AIMessage {
        get throws {
            guard let role=AIMessage.Role(rawValue:role) else {throw CocoaError(.fileReadCorruptFile)}
            return .init(role:role,text:text,image:image.map{AIImage(data:$0,mimeType:mime ?? "image/jpeg")})
        }
    }
}

@available(macOS 14,iOS 17,*)
enum StudySchema:VersionedSchema {
    static var versionIdentifier:Schema.Version { .init(1,0,0) }
    static var models:[any PersistentModel.Type] { [StoredStudy.self,StoredStudyVersion.self,StoredStudyMessage.self] }
}

@available(macOS 14,iOS 17,*)
enum StudyMigrations:SchemaMigrationPlan {
    static var schemas:[any VersionedSchema.Type] { [StudySchema.self] }
    static var stages:[MigrationStage] { [] }
}
