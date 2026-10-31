import SwiftUI
import LearningCore

struct CourseGlossaryCatalog:Decodable {
    struct Term:Decodable,Identifiable,Hashable {
        struct Note:Decodable,Hashable {
            let kind:DocumentKind
            let path:String
            let anchor:String
            let label:String
            let documentLabel:String
            var target:ReaderDocumentTarget {.init(kind:kind,path:path,anchor:anchor)}
        }
        let id:String
        let term:String
        let aliases:[String]
        let subject:String
        let body:String
        let notes:[Note]
        let related:[String]
    }
    let terms:[Term]
}
struct GlossaryPresentation:Identifiable {
    let id=UUID()
    let catalog:CourseGlossaryCatalog
    let courseID:String
    let selected:[String]
}
struct NativeGlossaryView:View {
    let presentation:GlossaryPresentation
    let onOpen:(ReaderDocumentTarget)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    @State private var subject=""
    @State private var path:[CourseGlossaryCatalog.Term]=[]
    @State private var initialized=false
    private var terms:[CourseGlossaryCatalog.Term] {
        presentation.catalog.terms.filter { term in
            (presentation.selected.isEmpty || presentation.selected.contains(term.id)) && (subject.isEmpty || term.subject==subject) &&
            (query.isEmpty || ([term.term,term.subject,term.body]+term.aliases).contains{$0.localizedCaseInsensitiveContains(query)})
        }
    }
    var body:some View {
        NavigationStack(path:$path) {
            List {
                Section {
                    Picker("学科",selection:$subject) {
                        Text("全部学科").tag("")
                        ForEach(Array(Set(presentation.catalog.terms.map(\.subject))).sorted(),id:\.self){Text($0).tag($0)}
                    }
                }
                Section {
                    ForEach(terms){term in
                        NavigationLink(value:term){VStack(alignment:.leading,spacing:5){Text(term.term).foregroundStyle(.primary);Text(term.subject).font(.caption).foregroundStyle(.secondary)}}
                    }
                } footer:{Text("点击术语查看定义、例子和相关笔记。自动标注可在设置的阅读辅助中调整。")}
            }
            .overlay{if terms.isEmpty {ContentUnavailableView.search(text:query)}}
            .searchable(text:$query,prompt:"搜索术语、别名或释义")
            .navigationTitle(presentation.selected.isEmpty ? "课程术语库":"选择术语含义")
            .navigationDestination(for:CourseGlossaryCatalog.Term.self){term in
                NativeTermDetail(term:term,catalog:presentation.catalog,courseID:presentation.courseID,onRelated:{path.append($0)},onClose:{dismiss()},onOpen:{dismiss();onOpen($0)})
            }
            .toolbar{if path.isEmpty {ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}}}}
            .onAppear{guard !initialized else {return};initialized=true;if presentation.selected.count==1,let term=presentation.catalog.terms.first(where:{$0.id==presentation.selected[0]}),path.isEmpty {path=[term]}}
        }
    }
}

struct NativeTermDetail:View {
    let term:CourseGlossaryCatalog.Term
    let catalog:CourseGlossaryCatalog
    let courseID:String
    let onRelated:(CourseGlossaryCatalog.Term)->Void
    let onClose:()->Void
    let onOpen:(ReaderDocumentTarget)->Void
    @EnvironmentObject private var practice:PracticeWorkspace
    @State private var expanded=false
    @State private var height:Double=280
    @State private var renderingIssue:String?
    private var saved:Bool {practice.items.contains{$0.source?.courseID==courseID && $0.source?.path==term.id && $0.kind=="knowledge" && $0.scheduled}}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Label(term.subject,systemImage:"book.closed").font(.subheadline).foregroundStyle(.secondary)
                MarkdownContentView(markdown:term.body,onHeight:{height=$0},onIssue:{renderingIssue=$0})
                    .environment(\.courseGlossary,nil)
                    .frame(height:expanded ? max(100,height):min(300,max(100,height))).clipped()
                Button(expanded ? "收起详细内容":"展开阅读全文",systemImage:expanded ? "chevron.up":"chevron.down"){expanded.toggle()}
                    .accessibilityValue(expanded ? "已展开":"已收起")
                if let renderingIssue {Text(renderingIssue).foregroundStyle(.red)}
                if !term.notes.isEmpty {
                    Text("相关笔记").font(.headline)
                    ForEach(term.notes,id:\.self){note in
                        Button{onOpen(note.target)}label:{HStack(alignment:.top){Image(systemName:"doc.text");VStack(alignment:.leading){Text(note.documentLabel);Text(note.label).font(.caption)};Spacer();Image(systemName:"chevron.right")}.foregroundStyle(.tint)}.buttonStyle(.plain)
                    }
                }
                if !term.related.isEmpty {
                    Text("相关术语").font(.headline)
                    ForEach(catalog.terms.filter{term.related.contains($0.id)}){item in Button(item.term){onRelated(item)}.buttonStyle(.bordered)}
                }
                Button(saved ? "已加入复习":"加入知识点复习",systemImage:saved ? "checkmark.circle":"calendar.badge.plus") {
                    practice.captureKnowledge(id:term.id,title:term.term,body:term.body,courseID:courseID)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(saved)
                if let issue=practice.issue {Text(issue).foregroundStyle(.red)}
            }.padding()
        }.navigationTitle(term.term).navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.confirmationAction){Button("完成",action:onClose)}}
    }
}

struct GlossaryMarkdownContent:View {
    let markdown:String
    @Environment(\.courseGlossary) private var glossary
    @State private var presentation:GlossaryPresentation?
    var body:some View {
        MarkdownContentView(markdown:markdown,onPresentTerm:{ids in
            if let glossary {presentation=GlossaryPresentation(catalog:glossary.catalog,courseID:glossary.courseID,selected:ids)}
        })
        .sheet(item:$presentation){value in NativeGlossaryView(presentation:value,onOpen:{glossary?.open($0)})}
    }
}
