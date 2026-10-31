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
    let id:UUID
    @EnvironmentObject private var practice:PracticeWorkspace
    @State private var reveal=false
    var body:some View {
        if let item=practice.items.first(where:{$0.id==id}) {
            VStack {
                StudyComparisonView(question:item.question){
                    if reveal {MarkdownContentView(markdown:item.answer.isEmpty ? "暂无参考答案，可回到原题使用讲一讲。":item.answer)}
                    else {Button("查看答案"){reveal=true}}
                }
                if reveal {HStack{ForEach(Array(["忘记","困难","掌握","轻松"].enumerated()),id:\.offset){index,title in Button(title){practice.grade(item,index+1);reveal=false}}}.padding()}
                Toggle("收藏",isOn:Binding(get:{item.favorite},set:{value in practice.update(item){$0.favorite=value}}))
                Toggle("错题",isOn:Binding(get:{item.mistake},set:{value in practice.update(item){$0.mistake=value}}))
                Toggle("安排复习",isOn:Binding(get:{item.scheduled},set:{value in practice.update(item){$0.scheduled=value}}))
                Button("撤销上次评分"){practice.undo(item)}.disabled(item.reviews.isEmpty)
            }.padding(.horizontal).navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        }
    }
}
