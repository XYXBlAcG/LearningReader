import SwiftUI
import AICore

struct StudyComparisonView<Answer:View>:View {
    let question:String
    var image:AIImage?
    @ViewBuilder let answer:()->Answer
    @State private var share=1.0/3.0
    @State private var dragStart:Double?
    @State private var collapsed=false
    @State private var expanded=false
    private var questionMarkdown:String {
        guard let image else { return question }
        return "![题图](data:"+image.mimeType+";base64,"+image.data.base64EncodedString()+")\n\n"+question
    }
    var body:some View {
        GeometryReader { geometry in
            VStack(spacing:0) {
                HStack {
                    Text("题目／所选内容").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { expanded=true } label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}.accessibilityLabel("展开题目")
                    Button { collapsed.toggle() } label:{Image(systemName:collapsed ? "chevron.down":"chevron.up")}.accessibilityLabel(collapsed ? "显示题目":"收起题目")
                }.padding(.horizontal).padding(.vertical,6)
                if !collapsed {
                    MarkdownContentView(markdown:questionMarkdown).frame(height:max(60,geometry.size.height*share-35))
                    Capsule().fill(.secondary.opacity(0.3)).frame(width:44,height:4).frame(maxWidth:.infinity).frame(height:14).contentShape(Rectangle())
                        .gesture(DragGesture().onChanged{value in
                            if dragStart==nil {dragStart=share}
                            share=min(0.65,max(0.15,(dragStart ?? share)+value.translation.height/max(1,geometry.size.height)))
                        }.onEnded{_ in dragStart=nil})
                        .accessibilityLabel("调整题目区域高度")
                        .accessibilityAdjustableAction{direction in share=min(0.65,max(0.15,share+(direction == .increment ? 0.05 : -0.05)))}
                }
                answer().frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        .sheet(isPresented:$expanded) {
            NavigationStack {
                MarkdownContentView(markdown:questionMarkdown).navigationTitle("题目")
                    .toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){expanded=false}}}
            }
        }
    }
}

struct ReferenceStudy:Identifiable {
    let id=UUID()
    let questions:[StudyQuestion]
    let document:String
}

struct ReferenceStudyView:View {
    let study:ReferenceStudy
    @EnvironmentObject private var ai:AIWorkspace
    @EnvironmentObject private var library:StudyWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var selected=0
    @StateObject private var interaction=AIInteraction()
    @State private var saved=false
    var body:some View {
        NavigationStack {
            if !study.questions.isEmpty {
                let item=study.questions[selected]
                VStack(spacing:0) {
                    Picker("选择题目",selection:$selected) {
                        ForEach(study.questions.indices,id:\.self){index in Text(study.questions[index].label).tag(index)}
                    }.pickerStyle(.menu)
                    StudyComparisonView(question:item.question) {
                        if item.answer.isEmpty {
                            ContentUnavailableView("未找到明确对应的答案",systemImage:"questionmark",description:Text("请回到原文核对答案，或使用讲一讲。"))
                        } else {MarkdownContentView(markdown:item.answer)}
                    }.id(item.id)
                    HStack {
                        Button("上一题"){selected-=1}.disabled(selected==0)
                        Spacer()
                        Button("讲一讲"){
                            var source=item.source
                            interaction.explain(.init(title:item.label,text:item.question,document:study.document,question:item.question,source:source),workspace:ai)
                        }
                        if library.records.contains(where:{$0.questionDigest==StudySource.hash(item.question) && $0.source?.courseID==item.source?.courseID && $0.source?.path==item.source?.path && $0.source?.anchor==item.source?.anchor}) { Button("已有讲解"){saved=true} }
                        Spacer()
                        Button("下一题"){selected+=1}.disabled(selected==study.questions.count-1)
                    }.padding()
                }
                .navigationTitle("参考答案").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("完成"){dismiss()}}}
                .sheet(isPresented:$saved){StudyLibraryView(courseID:item.source?.courseID,question:item.question,source:item.source)}
            }
        }.modifier(AIHost(interaction:interaction))
    }
}
