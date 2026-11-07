import Foundation
import Combine

struct LearningLocation:Codable,Equatable,Identifiable {
    var id:String {key}
    let courseKey:String
    let courseID:String
    let kind:String
    let path:String
    let title:String
    var key:String {courseKey+":"+kind+":"+path}
    init(courseKey:String,courseID:String,kind:String,path:String,title:String){self.courseKey=courseKey;self.courseID=courseID;self.kind=kind;self.path=path;self.title=title}

}
struct ChapterReview:Codable,Identifiable {
    var id=UUID()
    let source:LearningLocation
    var due:Date
    var updatedAt=Date()
}
struct LearningEvent:Codable,Identifiable {
    enum Kind:String,Codable {case opened,chapterReviewed}
    var id=UUID()
    let deviceID:UUID
    let kind:Kind
    let source:LearningLocation
    let date:Date
}
struct LearningArchive:Codable {
    var version=1
    var deviceID=UUID()
    var events:[LearningEvent]=[]
    var chapters:[ChapterReview]=[]
}
struct LearningJournalStore {
    private(set) var archive:LearningArchive
    let url:URL
    init(url:URL)throws {
        self.url=url
        archive=FileManager.default.fileExists(atPath:url.path) ? try JSONDecoder().decode(LearningArchive.self,from:Data(contentsOf:url)):LearningArchive()
        guard archive.version==1 else{throw CocoaError(.fileReadCorruptFile)}
    }
    mutating func schedule(_ source:LearningLocation,date:Date)throws {
        var next=archive
        if let index=next.chapters.firstIndex(where:{$0.source.key==source.key}){next.chapters[index].due=date;next.chapters[index].updatedAt=Date()}
        else{next.chapters.append(ChapterReview(source:source,due:date))}
        try save(next)
    }
    mutating func record(_ source:LearningLocation,at date:Date)throws {
        guard archive.events.last.map({$0.kind == .opened && $0.source==source && date.timeIntervalSince($0.date)<60}) != true else{return}
        var next=archive;next.events.append(LearningEvent(deviceID:archive.deviceID,kind:.opened,source:source,date:date));try save(next)
    }
    mutating func complete(_ id:UUID,at date:Date)throws {
        guard let chapter=archive.chapters.first(where:{$0.id==id}) else{throw CocoaError(.fileNoSuchFile)}
        var next=archive;next.chapters.removeAll{$0.id==id};next.events.append(LearningEvent(deviceID:archive.deviceID,kind:.chapterReviewed,source:chapter.source,date:date));try save(next)
    }
    private mutating func save(_ next:LearningArchive)throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(next).write(to:url,options:.atomic);archive=next
    }
}
@MainActor final class LearningJournal:ObservableObject {
    @Published private(set) var archive=LearningArchive()
    @Published var issue:String?
    private var store:LearningJournalStore?
    init(){do{let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0];let loaded=try LearningJournalStore(url:root.appendingPathComponent("LearningReader/Learning/journal.json"));store=loaded;archive=loaded.archive}catch{issue=error.localizedDescription}}
    func record(_ source:LearningLocation){perform{try $0.record(source,at:Date())}}
    func schedule(_ source:LearningLocation,date:Date){perform{try $0.schedule(source,date:date)}}
    func complete(_ id:UUID){perform{try $0.complete(id,at:Date())}}
    private func perform(_ action:(inout LearningJournalStore)throws->Void){do{guard var next=store else{throw CocoaError(.fileReadUnknown)};try action(&next);store=next;archive=next.archive;issue=nil}catch{issue=error.localizedDescription}}
}
