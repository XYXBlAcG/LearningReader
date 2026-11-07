import SwiftUI
import PracticeCore
import AICore
import LearningCore
import UserNotifications

@MainActor
final class PracticeWorkspace:NSObject,ObservableObject,UNUserNotificationCenterDelegate {
    var onOpen:(()->Void)?
    var onOpenQuestion:((UUID)->Void)?
    private var notificationTask:Task<Void,Never>?
    @Published private(set) var items:[PracticeItem]=[]
    @Published private(set) var settings=PracticeSettings()
    @Published private(set) var session: ReviewSession?
    @Published var issue:String?
    private var store:PracticeStore?
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate=self
        do {
            let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            store=try PracticeStore(url:root.appendingPathComponent("LearningReader/Practice/library.json"))
            reload()
        } catch {issue=error.localizedDescription}
    }
    func captureCheckpoint(_ location:CheckpointLocation,courseID:String) {
        guard settings.automaticMistakes else {return}
        perform {
            guard let store else {throw CocoaError(.fileReadUnknown)}
            let question=location.question
            let stem=question.stem+"\n\n"+question.options.map{$0.id+". "+$0.text}.joined(separator:"\n\n")
            let answer="正确选项："+question.correct.joined(separator:", ")+"\n\n"+question.explanation
            let id=try store.capture(title:question.concept,question:stem,answer:answer,source:StudySource(courseID:courseID,kind:location.kind.rawValue,path:location.path,anchor:question.id))
            try store.update(id){$0.mistake=true;$0.scheduled=true}
        }
    }
    func captureKnowledge(id:String,title:String,body:String,courseID:String) {
        perform {
            guard let store else {throw CocoaError(.fileReadUnknown)}
            let key=try store.capture(title:title,question:"请回忆“"+title+"”的定义、适用条件，并举一个例子。",answer:body,source:StudySource(courseID:courseID,kind:"glossary",path:id),kind:"knowledge")
            try store.update(key){$0.scheduled=true}
        }
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping()->Void) {
        if response.notification.request.content.userInfo["practice"] as? Bool == true {Task{@MainActor in if let value=response.notification.request.content.userInfo["questionID"] as? String,let id=UUID(uuidString:value),self.items.contains(where:{$0.id==id}) {self.onOpenQuestion?(id)}else{self.onOpen?()}}}
        completionHandler()
    }
    func refresh(){reschedule()}
    func capture(_ question:StudyQuestion,mistake:Bool) {
        perform {
            guard let store else {throw CocoaError(.fileReadUnknown)}
            let id=try store.capture(title:question.label,question:question.question,answer:question.answer,source:question.source)
            try store.update(id){if mistake {$0.mistake=true;$0.scheduled=true} else {$0.favorite.toggle()}}
        }
    }
    func editQuestion(_ question:StudyQuestion,change:(inout PracticeItem)->Void){perform{
        guard let store else {throw CocoaError(.fileReadUnknown)}
        let id=try store.capture(title:question.label,question:question.question,answer:question.answer,source:question.source)
        try store.update(id,change:change)
    }}
    func update(_ item:PracticeItem,change:(inout PracticeItem)->Void){perform{try store?.update(item.id,change:change)}}
    func grade(_ item:PracticeItem,_ grade:Int){perform{try store?.review(item.id,grade:grade,now:Date(),evidence:session?.evidence)}}
    func begin(_ id: UUID, ids: [UUID]? = nil) {
        guard session?.current != id else { return }
        let tail = items.filter { $0.scheduled && $0.card.due <= Date() && $0.id != id }.sorted { $0.card.due < $1.card.due }
        let remaining = (ids ?? tail.map(\.id)).filter { $0 != id }
        perform { try store?.startSession(ids: Array(([id] + remaining).prefix(settings.dailyLimit))) }
    }
    func reveal(_ visible: Bool) { perform { try store?.revealSession(visible) } }
    func deferCurrent() { perform { try store?.deferCurrent() } }
    func saveEvidence(_ evidence: ReviewEvidence) { perform { try store?.saveEvidence(evidence) } }
    func undo(_ item:PracticeItem){perform{try store?.undoReview(item.id)}}
    func configure(_ settings:PracticeSettings){perform{try store?.configure(settings)}}
    func summary()->String {store?.summary(now:Date()) ?? "无法读取学习记录"}
    func authorize() async {
        do {
            let granted=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])
            var updated=settings;updated.reminders=granted;configure(updated)
            if !granted {issue="通知未开启，仍可在今日复习中学习。"}
        }catch{issue=error.localizedDescription}
    }
    private func perform(_ operation:() throws->Void){do{guard store != nil else {throw CocoaError(.fileReadUnknown)};try operation();issue=nil;reload();reschedule()}catch{issue=error.localizedDescription}}
    private func reload(){items=store?.items ?? [];settings=store?.settings ?? PracticeSettings();session=store?.session}
    private func reschedule(){
        let settings=settings,items=items
        notificationTask?.cancel()
        notificationTask=Task {
            let generation=UUID().uuidString
            let center=UNUserNotificationCenter.current()
            let existing=await center.pendingNotificationRequests()
            guard !Task.isCancelled else {return}
            center.removePendingNotificationRequests(withIdentifiers:existing.filter{$0.identifier.hasPrefix("practice-")}.map(\.identifier))
            guard settings.reminders else {return}
            let permission=await center.notificationSettings()
            guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional else {return}
            let calendar=Calendar.current,now=Date()
            for offset in 0..<14 {
                guard let day=calendar.date(byAdding:.day,value:offset,to:now),let time=calendar.date(bySettingHour:settings.hour,minute:settings.minute,second:0,of:day),time>now else {continue}
                let due=items.filter{$0.scheduled && $0.card.due<=time}.sorted{$0.card.due<$1.card.due}
                guard !due.isEmpty else {continue}
                let content=UNMutableNotificationContent();content.title="今日复习";content.sound = .default
                content.body=settings.preview ? String(NotificationPreview.text(due[0].question).prefix(100)) : "有待复习的题目与知识点，打开知序开始回忆。"
                content.userInfo=["practice":true,"questionID":due[0].id.uuidString]
                let trigger=UNCalendarNotificationTrigger(dateMatching:calendar.dateComponents([.year,.month,.day,.hour,.minute],from:time),repeats:false)
                let identifier="practice-"+generation+"-\(offset)"
                guard !Task.isCancelled else {return}
                do {
                    try await center.add(UNNotificationRequest(identifier:identifier,content:content,trigger:trigger))
                    if Task.isCancelled {center.removePendingNotificationRequests(withIdentifiers:[identifier]);return}
                }catch{issue=error.localizedDescription}
            }
        }
    }
}
