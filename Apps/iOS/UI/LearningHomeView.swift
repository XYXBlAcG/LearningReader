import SwiftUI
import LearningCore
import PracticeCore

struct LearningHomeView:View {
    @ObservedObject var model:ReaderModel
    @ObservedObject var reader:ReaderController
    @ObservedObject var journal:LearningJournal
    @EnvironmentObject private var practice:PracticeWorkspace
    let onContinue:()->Void
    let onReview:(UUID)->Void
    let onOpen:(LearningLocation)->Void
    let onSettings:()->Void
    let onCourses:()->Void
    let onClassroom:()->Void
    @State private var date=Date()
    @State private var followingToday=true
    @Environment(\.scenePhase) private var scenePhase
    @State private var month=false
    @State private var chapter:ChapterReview?
    private var day:DateInterval {Calendar.current.dateInterval(of:.day,for:date)!}
    private var today:Bool {Calendar.current.isDateInToday(date)}
    private var due:[PracticeItem] {
        guard day.end>Date() else{return []}
        return practice.items.filter{$0.scheduled && $0.card.due<day.end}.sorted{$0.card.due<$1.card.due}
    }
    private var reviewed:Int {practice.items.flatMap(\.reviews).filter{($0.date>=day.start && $0.date<day.end)}.count}
    var body:some View {
        List {
            Section {
                HStack{Text(date.formatted(.dateTime.month().day().weekday()));Spacer();Button(month ? "收起月历":"月历"){month.toggle()}}
                if month {DatePicker("学习日期",selection:$date,displayedComponents:.date).datePickerStyle(.graphical)}else{week}
                Text("完成复习 \(reviewed) 次 · 章节回顾 \(journal.archive.events.filter{$0.kind == .chapterReviewed && ($0.date>=day.start && $0.date<day.end)}.count) 次").font(.caption).foregroundStyle(.secondary)
                if !today {Button("回到今天"){date=Date()}}
            }
            Section("继续学习") {
                if let state=reader.state,state.hasDocument {Button(action:onContinue){Label(state.title,systemImage:"book")}}
                else if let course=model.selected {Button("继续“"+course.title+"”",action:onContinue)}
                else{Button("选择课程内容",action:onCourses)}
            }
            if day.end>Date() {
                Section(today ? "今日复习":"预计待复习") {
                    let questions=due.filter{$0.kind=="question"}.count
                    Text("题目 \(questions) 道 · 知识点 \(due.count-questions) 个 · 本轮最多 \(practice.settings.dailyLimit) 项").font(.subheadline)
                    if let current=practice.session?.current,today {Button("继续本轮"){onReview(current)}}
                    else if let first=due.first,today {Button("开始今日复习"){onReview(first.id)}}
                    if due.isEmpty {Label("暂无到期复习",systemImage:"checkmark.circle").foregroundStyle(.secondary)}
                    ForEach(Array(due.prefix(3))){item in Button{onReview(item.id)}label:{VStack(alignment:.leading,spacing:5){Text(NotificationPreview.text(item.title));Text(NotificationPreview.text(item.question)).font(.caption).foregroundStyle(.secondary).lineLimit(2)}}.disabled(!today)}
                    if !today {Text("按当前安排预估，之后的评分可能改变日期。").font(.caption).foregroundStyle(.secondary)}
                }
            } else {
                Section("实际复习记录") {
                    ForEach(practice.items.filter{$0.reviews.contains{($0.date>=day.start && $0.date<day.end)}}){item in Text(NotificationPreview.text(item.title))}
                    if reviewed==0 {Text("这一天没有已记录的评分").foregroundStyle(.secondary)}
                }
            }
            Section("课堂记录"){Button("记关键词、收集照片与课件",systemImage:"pencil.and.list.clipboard",action:onClassroom)}
            Section("待回顾章节") {
                let chapters=journal.archive.chapters.filter{$0.due<day.end}.sorted{$0.due<$1.due}
                ForEach(chapters){item in Button{chapter=item}label:{VStack(alignment:.leading){Text(item.source.title);Text(item.due.formatted(date:.abbreviated,time:.omitted)).font(.caption).foregroundStyle(.secondary)}}}
                if chapters.isEmpty {Text("在学习页菜单中将当前章节加入回顾").foregroundStyle(.secondary)}
            }
            Section("当日阅读") {
                ForEach(journal.archive.events.filter{$0.kind == .opened && ($0.date>=day.start && $0.date<day.end)}.reversed()){event in Button{onOpen(event.source)}label:{Text(event.source.title)}}
                Text("阅读记录仅表示打开过内容，不代表已经掌握。").font(.caption).foregroundStyle(.secondary)
            }
            if let issue=journal.issue {Section{Text(issue).foregroundStyle(.red)}}
        }.navigationTitle("今天")
        .toolbar{ToolbarItem(placement:.primaryAction){Button("设置",systemImage:"gearshape",action:onSettings)}}
        .onChange(of:date){_,value in followingToday=Calendar.current.isDateInToday(value)}
        .onChange(of:scenePhase){_,phase in if phase == .active && followingToday {date=Date()}}
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.significantTimeChangeNotification)){_ in if followingToday {date=Date()}}
        .sheet(item:$chapter){item in ChapterReviewEditor(source:item.source,existing:item,journal:journal,onRead:{onOpen(item.source)})}
    }
    private var week:some View {
        let calendar=Calendar.current
        let start=calendar.dateInterval(of:.weekOfYear,for:date)!.start
        return HStack(spacing:2){ForEach(0..<7){offset in
            let value=calendar.date(byAdding:.day,value:offset,to:start)!
            Button{date=value}label:{VStack{Text(value.formatted(.dateTime.weekday(.narrow)));Text(value.formatted(.dateTime.day()));let count=practice.items.flatMap(\.reviews).filter{calendar.isDate($0.date,inSameDayAs:value)}.count;Text(count>0 ? "•":" ")}.font(.caption).frame(maxWidth:.infinity).padding(.vertical,4)}.buttonStyle(.bordered).tint(calendar.isDate(value,inSameDayAs:date) ? .accentColor:.secondary).accessibilityLabel(value.formatted(date:.complete,time:.omitted))
        }}
    }
}

struct ChapterReviewEditor:View {
    let source:LearningLocation
    var existing:ChapterReview?
    @ObservedObject var journal:LearningJournal
    let onRead:()->Void
    @State private var date:Date
    @Environment(\.dismiss) private var dismiss
    init(source:LearningLocation,existing:ChapterReview?=nil,journal:LearningJournal,onRead:@escaping()->Void){self.source=source;self.existing=existing;self.journal=journal;self.onRead=onRead;_date=State(initialValue:existing?.due ?? Date())}
    var body:some View {
        NavigationStack{Form{
            Section{Text(source.title);DatePicker("回顾日期",selection:$date,displayedComponents:.date)}
            Section("回顾建议"){Text("回忆核心定义与适用条件");Text("梳理关键证明");Text("独立完成一道代表题");Button("打开原文"){dismiss();onRead()}}
            if let existing {Section{Button("已完成章节回顾"){journal.complete(existing.id);if journal.issue==nil {dismiss()}}}}
            if let issue=journal.issue {Text(issue).foregroundStyle(.red)}
        }.navigationTitle("章节回顾").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("保存安排"){journal.schedule(source,date:date);if journal.issue==nil {dismiss()}}}}}
    }
}
