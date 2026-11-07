import SwiftUI
import PracticeCore
import UniformTypeIdentifiers

struct PracticeLibraryView:View {
    var courseTitles: [String: String] = [:]
    @EnvironmentObject private var practice:PracticeWorkspace
    @EnvironmentObject private var library:StudyWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var filter=0
    @State private var exporting=false
    @State private var search = ""
    @State private var course = ""
    @State private var kind = ""
    private var visible:[PracticeItem] {
        practice.items
            .filter { item in
                switch filter {
                case 0: return item.scheduled && item.card.due <= Date()
                case 1: return item.favorite
                default: return item.mistake
                }
            }
            .filter { (course.isEmpty || $0.source?.courseID == course) && (kind.isEmpty || $0.kind == kind) }
            .filter { search.isEmpty || ($0.title + $0.question + ($0.source?.path ?? "")).localizedCaseInsensitiveContains(search) }
            .sorted { $0.card.due < $1.card.due }
    }
    var body:some View {
        NavigationStack {
            List {
                Picker("范围",selection:$filter){Text("今日复习").tag(0);Text("收藏").tag(1);Text("错题集").tag(2)}.pickerStyle(.segmented)
                Picker("来源课程", selection: $course) {
                    Text("全部课程").tag("")
                    ForEach(Array(Set(practice.items.compactMap { $0.source?.courseID })).sorted(), id: \.self) { id in
                        Text(courseTitles[id] ?? "课程 " + String(id.suffix(6))).tag(id)
                    }
                }
                Picker("类型", selection: $kind) { Text("全部").tag(""); Text("题目").tag("question"); Text("知识点").tag("knowledge") }
                if filter == 0 {
                    Text("到期 \(visible.count) 题 · 每轮最多 \(practice.settings.dailyLimit) 题").foregroundStyle(.secondary)
                    if let id = practice.session?.current ?? visible.first?.id {
                        NavigationLink(practice.session?.current == nil ? "开始本轮" : "继续本轮") { PracticeDetailView(id: id, queue: visible.map(\.id)) }
                    } else { ContentUnavailableView("暂无到期题目", systemImage: "checkmark.circle") }
                }
                ForEach(Array(visible.prefix(filter==0 ? practice.settings.dailyLimit : visible.count))){item in
                    NavigationLink{PracticeDetailView(id:item.id, queue: visible.map(\.id))}label:{VStack(alignment:.leading){Text(item.title);Text(item.card.due.formatted()).font(.caption).foregroundStyle(.secondary)}}
                }

            }.navigationTitle("学习记录")
            .searchable(text: $search, prompt: "搜索题目或来源")
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("完成"){dismiss()}}
                ToolbarItem(placement:.primaryAction){Button("导出摘要"){exporting=true}}
            }
            .fileExporter(isPresented:$exporting,document:StudyDataDocument(data:Data((practice.summary()+"\n\n## 已保存的 AI 讲解\n\n"+library.records.map{$0.title+" · "+$0.updatedAt.formatted()}.joined(separator:"\n")).utf8)),contentType:UTType(importedAs:"net.daringfireball.markdown"),defaultFilename:"知序学习摘要.md"){result in if case .failure(let error)=result {practice.issue=error.localizedDescription}}
            .alert("学习记录",isPresented:Binding(get:{practice.issue != nil},set:{if !$0 {practice.issue=nil}})){Button("知道了"){practice.issue=nil}}message:{Text(practice.issue ?? "")}
        }
    }
}
struct PracticeDetailView:View {
    private let queue: [UUID]?
    @State private var currentID:UUID
    @EnvironmentObject private var practice:PracticeWorkspace
    @State private var reveal=false
    @State private var lastReviewed:UUID?
    @State private var finished=false
    @State private var notes=false
    @State private var evidence = false
    @State private var editingAnswer = false
    init(id:UUID, queue: [UUID]? = nil){_currentID=State(initialValue:id); self.queue = queue}
    var body:some View {
        if finished {
            ContentUnavailableView {
                Label("本轮已结束",systemImage:"checkmark.circle")
            } description:{Text("稍后处理的题目仍保留在到期列表。")} actions:{Button("撤销上次评分"){
                if let id=lastReviewed,let item=practice.items.first(where:{$0.id==id}) {practice.undo(item);if practice.issue==nil {currentID=id;reveal=true;finished=false;lastReviewed=nil}}
            }}
        } else if let item=practice.items.first(where:{$0.id==currentID}) {
            VStack(spacing:16) {
                if let session = practice.session {
                    Text("本轮 \(min(session.position + 1, session.ids.count)) / \(session.ids.count)").font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(session.position), total: Double(max(1, session.ids.count))).padding(.horizontal)
                }
                MarkdownContentView(markdown:item.question + (reveal ? "\n\n---\n\n## 参考答案\n\n" + (item.answer.isEmpty ? "暂无参考答案，可在题目笔记中补充或稍后处理。" : item.answer) : "")).id(currentID.uuidString+(reveal ? "-answer":"-question"))
                Button("作答记录（自评）") { evidence = true }
                if reveal {
                    HStack(spacing:12){ForEach(ReviewConfidence.allCases){choice in
                        Button(choice.title){
                            practice.grade(item,choice.rawValue)
                            if practice.issue==nil {
                                lastReviewed=item.id;reveal=false
                                if let next=practice.session?.current {currentID=next}else{finished=true}
                            }
                        }.buttonStyle(.borderedProminent).tint(choice == .forgotten ? .red:choice == .uncertain ? .orange:.teal).frame(maxWidth:.infinity).controlSize(.large).disabled(item.answer.isEmpty)
                    }}.padding(.horizontal)
                } else {Button("显示答案"){practice.reveal(true);if practice.issue == nil {reveal=true}}.buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom)}
                Button("稍后处理") {
                    practice.deferCurrent()
                    if practice.issue == nil { reveal = false; if let next = practice.session?.current {currentID = next} else {finished = true} }
                }
                if let issue=practice.issue {Text(issue).foregroundStyle(.red)}
            }.navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.primaryAction){Menu {
                Button("题目笔记",systemImage:"square.and.pencil"){notes=true}
                Button("补充或修改参考答案", systemImage: "text.book.closed") { editingAnswer = true }
                NavigationLink("历史作答") { ReviewHistoryView(item: item) }
                if reveal {Button("隐藏答案"){practice.reveal(false);if practice.issue == nil {reveal=false}}}
                Toggle("收藏",isOn:Binding(get:{item.favorite},set:{value in practice.update(item){$0.favorite=value}}))
                Toggle("错题",isOn:Binding(get:{item.mistake},set:{value in practice.update(item){$0.mistake=value}}))
                Toggle("安排复习",isOn:Binding(get:{item.scheduled},set:{value in practice.update(item){$0.scheduled=value}}))
                Button("撤销上次评分"){
                    if let id=lastReviewed,let previous=practice.items.first(where:{$0.id==id}) {practice.undo(previous);if practice.issue==nil {currentID=id;lastReviewed=nil;reveal=true}}
                }.disabled(lastReviewed==nil)
            }label:{Image(systemName:"ellipsis.circle")}}}
            .sheet(isPresented:$notes){PracticeNoteEditor(item:item)}
            .sheet(isPresented: $evidence) { ReviewEvidenceEditor() }
            .sheet(isPresented: $editingAnswer) { PracticeAnswerEditor(item: item) }
            .onAppear {
                practice.begin(currentID, ids: queue)
                reveal = practice.session?.revealed ?? false
                lastReviewed = practice.session?.lastGraded
            }
        }
    }
}
