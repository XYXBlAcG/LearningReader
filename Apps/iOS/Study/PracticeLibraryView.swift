import SwiftUI
import PracticeCore
import UniformTypeIdentifiers

struct PracticeLibraryView:View {
    @EnvironmentObject private var practice:PracticeWorkspace
    @EnvironmentObject private var library:StudyWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var filter=0
    @State private var exporting=false
    private var visible:[PracticeItem] {
        practice.items.filter{filter==0 ? $0.scheduled && $0.card.due<=Date() : filter==1 ? $0.favorite : $0.mistake}.sorted{$0.card.due<$1.card.due}
    }
    var body:some View {
        NavigationStack {
            List {
                Picker("范围",selection:$filter){Text("今日复习").tag(0);Text("收藏").tag(1);Text("错题集").tag(2)}.pickerStyle(.segmented)
                ForEach(Array(visible.prefix(filter==0 ? practice.settings.dailyLimit : visible.count))){item in
                    NavigationLink{PracticeDetailView(id:item.id)}label:{VStack(alignment:.leading){Text(item.title);Text(item.card.due.formatted()).font(.caption).foregroundStyle(.secondary)}}
                }

            }.navigationTitle("学习记录")
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
    @State private var currentID:UUID
    @EnvironmentObject private var practice:PracticeWorkspace
    @State private var reveal=false
    @State private var lastReviewed:UUID?
    @State private var finished=false
    init(id:UUID){_currentID=State(initialValue:id)}
    var body:some View {
        if finished {
            ContentUnavailableView {
                Label("本次复习已完成",systemImage:"checkmark.circle")
            } description:{EmptyView()} actions:{Button("撤销上次评分"){
                if let id=lastReviewed,let item=practice.items.first(where:{$0.id==id}) {practice.undo(item);if practice.issue==nil {currentID=id;reveal=true;finished=false;lastReviewed=nil}}
            }}
        } else if let item=practice.items.first(where:{$0.id==currentID}) {
            VStack(spacing:16) {
                MarkdownContentView(markdown:reveal ? (item.answer.isEmpty ? "暂无参考答案，请回到原题补充讲解。":item.answer):item.question).id(currentID.uuidString+(reveal ? "-answer":"-question"))
                if reveal {
                    HStack(spacing:12){ForEach(ReviewConfidence.allCases){choice in
                        Button(choice.title){
                            practice.grade(item,choice.rawValue)
                            if practice.issue==nil {
                                lastReviewed=item.id;reveal=false
                                if let next=practice.items.filter({$0.scheduled && $0.card.due<=Date() && $0.id != item.id}).sorted(by:{$0.card.due<$1.card.due}).first {currentID=next.id}else{finished=true}
                            }
                        }.buttonStyle(.borderedProminent).tint(choice == .forgotten ? .red:choice == .uncertain ? .orange:.teal).frame(maxWidth:.infinity).controlSize(.large).disabled(item.answer.isEmpty)
                    }}.padding(.horizontal)
                } else {Button("显示答案"){reveal=true}.buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom)}
                if let issue=practice.issue {Text(issue).foregroundStyle(.red)}
            }.navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.primaryAction){Menu {
                if reveal {Button("回看题目"){reveal=false}}
                Toggle("收藏",isOn:Binding(get:{item.favorite},set:{value in practice.update(item){$0.favorite=value}}))
                Toggle("错题",isOn:Binding(get:{item.mistake},set:{value in practice.update(item){$0.mistake=value}}))
                Toggle("安排复习",isOn:Binding(get:{item.scheduled},set:{value in practice.update(item){$0.scheduled=value}}))
                Button("撤销上次评分"){
                    if let id=lastReviewed,let previous=practice.items.first(where:{$0.id==id}) {practice.undo(previous);if practice.issue==nil {currentID=id;lastReviewed=nil;reveal=true}}
                }.disabled(lastReviewed==nil)
            }label:{Image(systemName:"ellipsis.circle")}}}
        }
    }
}
