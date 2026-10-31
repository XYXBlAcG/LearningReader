import Foundation
import AICore
import FSRS

public struct PracticeReview:Codable,Sendable {
    public var date:Date
    public var grade:Int
    public var previous:Card
}
public struct PracticeItem:Codable,Identifiable,Sendable {
    public var id=UUID()
    public var title:String
    public var question:String
    public var answer:String
    public var source:StudySource?
    public var favorite=false
    public var mistake=false
    public var scheduled=false
    public var kind="question"
    public var card:Card
    public var reviews:[PracticeReview]=[]
    public var createdAt=Date()
    public var notes=""
}
public struct PracticeSettings:Codable,Sendable {
    public var retention=0.9
    public var dailyLimit=10
    public var reminders=false
    public var hour=20
    public var minute=0
    public var preview=false
    public var automaticMistakes=true
    public init() {}
}
public final class PracticeStore {
    private struct Archive:Codable {var version=1;var items:[PracticeItem]=[];var settings=PracticeSettings()}
    private var archive:Archive
    private let url:URL
    public var items:[PracticeItem] {archive.items}
    public var settings:PracticeSettings {archive.settings}
    public init(url:URL) throws {
        self.url=url
        archive=FileManager.default.fileExists(atPath:url.path) ? try JSONDecoder().decode(Archive.self,from:Data(contentsOf:url)) : Archive()
        guard archive.version==1 else {throw CocoaError(.fileReadCorruptFile)}
    }
    @discardableResult public func capture(title:String,question:String,answer:String,source:StudySource?,kind:String="question") throws -> UUID {
        if let existing=items.first(where:{$0.kind==kind && $0.source?.courseID==source?.courseID && $0.source?.kind==source?.kind && $0.source?.path==source?.path && $0.source?.anchor==source?.anchor && $0.question==question}) {return existing.id}
        var next=archive
        let item=PracticeItem(title:title,question:question,answer:answer,source:source,kind:kind,card:Card(due:Date()))
        next.items.append(item);try save(next);return item.id
    }
    public func update(_ id:UUID,change:(inout PracticeItem)->Void) throws {
        var next=archive
        guard let index=next.items.firstIndex(where:{$0.id==id}) else {throw CocoaError(.fileNoSuchFile)}
        change(&next.items[index]);try save(next)
    }
    public func configure(_ settings:PracticeSettings) throws {
        guard (0.7...0.99).contains(settings.retention),(1...100).contains(settings.dailyLimit),(0...23).contains(settings.hour),(0...59).contains(settings.minute) else {throw CocoaError(.fileReadCorruptFile)}
        var next=archive;next.settings=settings;try save(next)
    }
    public func review(_ id:UUID,grade:Int,now:Date) throws {
        guard let rating=Rating(rawValue:grade),rating != .manual else {throw CocoaError(.fileReadCorruptFile)}
        let scheduler=FSRS(parameters:.init(requestRetention:settings.retention,w:FSRSDefaults.defaultWv6))
        guard let item=items.first(where:{$0.id==id}) else {throw CocoaError(.fileNoSuchFile)}
        let next=try scheduler.next(card:item.card,now:now,grade:rating).card
        try update(id){$0.reviews.append(.init(date:now,grade:grade,previous:$0.card));$0.card=next}
    }

    public func undoReview(_ id:UUID) throws {try update(id){if let previous=$0.reviews.popLast() {$0.card=previous.previous}}}
    public func due(now:Date)->[PracticeItem] {Array(items.filter{$0.scheduled && $0.card.due<=now}.sorted{$0.card.due<$1.card.due}.prefix(settings.dailyLimit))}
    public func summary(now:Date)->String {
        let formatter=ISO8601DateFormatter()
        let pending=due(now:now)
        return "# 知序学习摘要\n\n更新时间："+formatter.string(from:now)+"\n\n收藏：\(items.filter(\.favorite).count)；错题：\(items.filter(\.mistake).count)；到期复习：\(pending.count)\n\n"+items.filter{$0.scheduled || $0.favorite || $0.mistake}.map{item in
            "## "+item.title+"\n\n类型："+item.kind+"；错题：\(item.mistake)；实际复习次数：\(item.reviews.count)；下次复习："+formatter.string(from:item.card.due)+"\n\n"+item.question+"\n\n个人记录："+item.notes+"\n\n来源："+(item.source?.path ?? "本地")
        }.joined(separator:"\n\n")
    }
    private func save(_ next:Archive) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(next).write(to:url,options:.atomic);archive=next
    }
}
