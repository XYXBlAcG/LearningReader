import Foundation
import AICore
import FSRS

public struct PracticeReview:Codable,Sendable {
    public var date:Date
    public var grade:Int
    public var previous:Card
    public var evidence:ReviewEvidence?
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
    private struct Archive:Codable {var version=1;var items:[PracticeItem]=[];var settings=PracticeSettings();var session:ReviewSession?}
    private var archive:Archive
    private let url:URL
    public var items:[PracticeItem] {archive.items}
    public var settings:PracticeSettings {archive.settings}
    public var session:ReviewSession? {archive.session}

    public func startSession(ids: [UUID]) throws {
        guard !ids.isEmpty, Set(ids).count == ids.count, ids.allSatisfy({ id in items.contains { $0.id == id } }) else { throw CocoaError(.fileReadCorruptFile) }
        var next = archive
        next.session = ReviewSession(ids: ids)
        try save(next)
    }

    public func revealSession(_ revealed: Bool) throws {
        var next = archive
        next.session?.revealed = revealed
        try save(next)
    }

    public func saveEvidence(_ evidence: ReviewEvidence) throws {
        try evidence.validate()
        var next = archive
        next.session?.evidence = evidence
        try save(next)
    }

    public func deferCurrent() throws {
        var next = archive
        if next.session?.current != nil { next.session?.position += 1; next.session?.revealed = false; next.session?.evidence = nil }
        try save(next)
    }
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
    public func review(_ id:UUID,grade:Int,now:Date,evidence:ReviewEvidence? = nil) throws {
        try evidence?.validate()
        if let session, session.ids.contains(id), session.current != id { throw CocoaError(.fileReadCorruptFile) }
        guard let rating=Rating(rawValue:grade),rating != .manual else {throw CocoaError(.fileReadCorruptFile)}
        let scheduler=FSRS(parameters:.init(requestRetention:settings.retention,w:FSRSDefaults.defaultWv6))
        guard let item=items.first(where:{$0.id==id}) else {throw CocoaError(.fileNoSuchFile)}
        let card=try scheduler.next(card:item.card,now:now,grade:rating).card
        var next = archive
        guard let index = next.items.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        next.items[index].reviews.append(.init(date:now,grade:grade,previous:item.card,evidence:evidence))
        next.items[index].card = card
        if next.session?.current == id {
            next.session?.position += 1
            next.session?.revealed = false
            next.session?.lastGraded = id
            next.session?.evidence = nil
        }
        try save(next)
    }

    public func undoReview(_ id:UUID) throws {
        var next = archive
        guard let index = next.items.firstIndex(where: { $0.id == id }), let previous = next.items[index].reviews.popLast() else { return }
        next.items[index].card = previous.previous
        if next.session?.lastGraded == id, let position = next.session?.ids.firstIndex(of: id) {
            next.session?.position = position
            next.session?.revealed = true
            next.session?.lastGraded = nil
            next.session?.evidence = previous.evidence
        }
        try save(next)
    }
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
