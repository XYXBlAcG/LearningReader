import Foundation

struct ClassroomAttachment:Codable,Identifiable {
    enum Kind:String,Codable {case image,pdf,text,presentation}
    let id:UUID
    let name:String
    let filename:String
    let kind:Kind
}
struct ClassroomDraft:Codable,Identifiable {
    var id=UUID()
    var text:String
    let sources:[ClassroomAttachment]
    var date=Date()
    var confirmed=false
    var keywords=""
    var model=""
}
struct ClassroomLesson:Codable,Identifiable {
    var id=UUID()
    var title:String
    var source:LearningLocation?
    var date=Date()
    var keywords=""
    var attachments:[ClassroomAttachment]=[]
    var drafts:[ClassroomDraft]=[]
}
final class ClassroomStore {
    private struct Archive:Codable {var version=1;var lessons:[ClassroomLesson]=[]}
    private var archive:Archive
    let root:URL
    var lessons:[ClassroomLesson] {archive.lessons}
    init(root:URL)throws {
        self.root=root
        let url=root.appendingPathComponent("lessons.json")
        archive=FileManager.default.fileExists(atPath:url.path) ? try JSONDecoder().decode(Archive.self,from:Data(contentsOf:url)):Archive()
        guard archive.version==1 else{throw CocoaError(.fileReadCorruptFile)}
    }
    func file(_ attachment:ClassroomAttachment)throws->URL {
        guard attachment.filename==URL(fileURLWithPath:attachment.filename).lastPathComponent,!attachment.filename.contains("..") else{throw CocoaError(.fileReadCorruptFile)}
        return root.appendingPathComponent("assets").appendingPathComponent(attachment.filename)
    }
    func importData(_ data:Data,name:String,kind:ClassroomAttachment.Kind)throws->ClassroomAttachment {
        guard data.count<=50*1024*1024 else{throw CocoaError(.fileReadTooLarge)}
        let id=UUID(),ext=URL(fileURLWithPath:name).pathExtension.filter{$0.isLetter || $0.isNumber}
        let item=ClassroomAttachment(id:id,name:name,filename:id.uuidString+(ext.isEmpty ? "":"."+ext),kind:kind)
        let url=try file(item)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic);return item
    }
    func save(_ lesson:ClassroomLesson)throws {
        var next=archive
        if let i=next.lessons.firstIndex(where:{$0.id==lesson.id}){next.lessons[i]=lesson}else{next.lessons.append(lesson)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try JSONEncoder().encode(next).write(to:root.appendingPathComponent("lessons.json"),options:.atomic);archive=next
    }
    func delete(_ id:UUID)throws {
        var next=archive;next.lessons.removeAll{$0.id==id}
        try JSONEncoder().encode(next).write(to:root.appendingPathComponent("lessons.json"),options:.atomic);archive=next
    }
}
