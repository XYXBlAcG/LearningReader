import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import AICore

struct ClassroomLibraryView:View {
    @ObservedObject var workspace:ClassroomWorkspace
    @ObservedObject var model:ReaderModel
    let source:LearningLocation?
    @Environment(\.dismiss) private var dismiss
    @State private var selection:ClassroomLesson?
    var body:some View {
        NavigationStack{List{
            if let issue=workspace.issue {Text(issue).foregroundStyle(.red)}
            ForEach(workspace.lessons.sorted{$0.date>$1.date}){lesson in Button{selection=lesson}label:{VStack(alignment:.leading){Text(lesson.title);Text(lesson.date.formatted()+" · \(lesson.attachments.count) 份资料").font(.caption).foregroundStyle(.secondary);if !lesson.drafts.isEmpty {Text(lesson.drafts.last?.confirmed==true ? "笔记已确认":"草稿待确认").font(.caption).foregroundStyle(.secondary)}}}.swipeActions{Button("删除",role:.destructive){workspace.delete(lesson.id)}}}
        }.navigationTitle("课堂记录").toolbar{ToolbarItem(placement:.cancellationAction){Button("完成"){dismiss()}};ToolbarItem(placement:.primaryAction){Button("新课堂",systemImage:"plus"){let lesson=ClassroomLesson(title:"课堂 "+Date().formatted(date:.abbreviated,time:.omitted),source:source);if workspace.save(lesson){selection=lesson}}}}
        .sheet(item:$selection){ClassroomEditor(initial:$0,workspace:workspace,model:model)}}
    }
}
struct ClassroomEditor:View {
    @ObservedObject var workspace:ClassroomWorkspace
    @ObservedObject var model:ReaderModel
    @EnvironmentObject private var ai:AIWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var lesson:ClassroomLesson
    @State private var selected=Set<UUID>()
    @State private var importFiles=false
    @State private var imageSource:AIImageSource?
    @State private var preview:URL?
    @State private var firstPage=1
    @State private var lastPage=10
    @State private var draft:ClassroomDraft?
    init(initial:ClassroomLesson,workspace:ClassroomWorkspace,model:ReaderModel){self.workspace=workspace;self.model=model;_lesson=State(initialValue:initial);_selected=State(initialValue:Set(initial.attachments.filter{$0.kind != .presentation}.map(\.id)))}
    var body:some View {
        NavigationStack{editorForm.navigationTitle("课堂记录").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){persist();if workspace.issue==nil {dismiss()}}}}
        .onChange(of:lesson.keywords){_,_ in persist()}.onChange(of:lesson.title){_,_ in persist()}.onChange(of:lesson.date){_,_ in persist()}.onChange(of:lesson.source){_,_ in persist()}
        .sheet(item:$imageSource){value in AIPhotoFlow(source:value){image in do{try workspace.add(image.data,name:"课堂照片.jpg",kind:.image,to:&lesson);selected=Set(lesson.attachments.filter{$0.kind != .presentation}.map(\.id));imageSource=nil}catch{workspace.issue=error.localizedDescription}}}
        .fileImporter(isPresented:$importFiles,allowedContentTypes:[.pdf,.image,.plainText,.presentation],allowsMultipleSelection:true){result in do{for url in try result.get(){let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}};let values=try url.resourceValues(forKeys:[.contentTypeKey,.fileSizeKey]);guard (values.fileSize ?? 0)<=50*1024*1024 else{throw CocoaError(.fileReadTooLarge)};let type=values.contentType;let kind:ClassroomAttachment.Kind=type?.conforms(to:.pdf)==true ? .pdf:type?.conforms(to:.image)==true ? .image:type?.conforms(to:.presentation)==true ? .presentation:.text;try workspace.add(Data(contentsOf:url),name:url.lastPathComponent,kind:kind,to:&lesson)};selected=Set(lesson.attachments.filter{$0.kind != .presentation}.map(\.id))}catch{workspace.issue=error.localizedDescription}}
        .sheet(isPresented:Binding(get:{preview != nil},set:{if !$0 {preview=nil}})){if let preview {ClassroomPreview(url:preview)}}
        .sheet(item:$draft){ClassroomDraftEditor(lessonID:lesson.id,initial:$0,workspace:workspace)}
        }
    }
    private var editorForm:some View {
Form{
            Section("课堂"){
                TextField("标题",text:$lesson.title)
                DatePicker("时间",selection:$lesson.date)
                Text(lesson.source?.title ?? "尚未关联章节").foregroundStyle(.secondary)
                if let course=model.selected,let snapshot=model.snapshot {
                    Picker("关联“\(course.title)”的章节",selection:Binding(get:{lesson.source?.courseID==course.id ? lesson.source?.path ?? "":""},set:{path in if let document=snapshot.course.documents.first(where:{$0.path==path}){lesson.source=LearningLocation(course:course,kind:document.kind.rawValue,path:path,title:URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent)}})){
                        Text("选择章节").tag("")
                        ForEach(snapshot.course.documents,id:\.path){document in Text(document.path).tag(document.path)}
                    }
                }
            }
            Section("关键词／课堂速记") {TextEditor(text:$lesson.keywords).frame(minHeight:140);Text("关键词与标题自动保存").font(.caption).foregroundStyle(.secondary)}
            Section("资料 · 勾选后发送给 AI") {
                ForEach(lesson.attachments){item in
                    HStack{Toggle(item.name,isOn:Binding(get:{selected.contains(item.id)},set:{if $0 {selected.insert(item.id)}else{selected.remove(item.id)}}));Button("查看"){do{preview=try workspace.file(item)}catch{workspace.issue=error.localizedDescription}}}

                }
                Button("拍照收集",systemImage:"camera"){imageSource = .camera}
                Button("从照片选择",systemImage:"photo"){imageSource = .library}
                Button("导入课件／文件",systemImage:"doc.badge.plus"){importFiles=true}
                Text("支持照片、PDF、UTF-8 文本。PPT 可收集查看，整理前需转成 PDF。单文件最多 50 MB。").font(.caption).foregroundStyle(.secondary)
            }
            Section("AI 整理") {
                Stepper("PDF 起始页 \(firstPage)",value:$firstPage,in:1...10000)
                Stepper("PDF 结束页 \(lastPage)",value:$lastPage,in:1...10000)
                Text("范围应用到本次选中的 PDF，每次每份最多 20 页；图片与页面会发送给已配置的图像服务。").font(.caption).foregroundStyle(.secondary)
                if workspace.running==lesson.id {ProgressView(workspace.status);Button("取消整理",role:.cancel){workspace.cancel()}}
                else{Button("生成整理草稿"){workspace.generate(lesson,selected:selected,firstPage:firstPage,lastPage:lastPage,ai:ai)}.disabled(workspace.running != nil || (lesson.keywords.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && selected.isEmpty))}
                if !workspace.status.isEmpty {Text(workspace.status).font(.caption)}
            }
            Section("整理草稿与个人笔记") {
                ForEach((workspace.lessons.first{$0.id==lesson.id} ?? lesson).drafts.reversed()){item in Button{draft=item}label:{VStack(alignment:.leading){Text(item.confirmed ? "已确认笔记":"待确认草稿");Text(item.date.formatted()).font(.caption).foregroundStyle(.secondary)}}}
            }
            if let issue=workspace.issue {Text(issue).foregroundStyle(.red)}
        }
    }
    private func persist(){if let saved=workspace.lessons.first(where:{$0.id==lesson.id}){lesson.drafts=saved.drafts};workspace.save(lesson)}
}
struct ClassroomDraftEditor:View {
    let lessonID:UUID
    @ObservedObject var workspace:ClassroomWorkspace
    @State private var draft:ClassroomDraft
    @State private var editing=false
    @State private var preview:URL?
    @Environment(\.dismiss) private var dismiss
    init(lessonID:UUID,initial:ClassroomDraft,workspace:ClassroomWorkspace){self.lessonID=lessonID;self.workspace=workspace;_draft=State(initialValue:initial)}
    var body:some View {
        NavigationStack{VStack{
            Picker("内容模式",selection:$editing){Text("阅读").tag(false);Text("编辑").tag(true)}.pickerStyle(.segmented).padding(.horizontal)
            if editing {TextEditor(text:$draft.text).padding()}else{MarkdownContentView(markdown:draft.text)}
            DisclosureGroup("本次使用的来源（与 [S序号 p页码] 对照）") {Text("关键词快照："+draft.keywords).font(.caption);Text("模型："+draft.model).font(.caption);ForEach(Array(draft.sources.enumerated()),id:\.element.id){index,item in Button("S\(index+1) · "+item.name){do{preview=try workspace.file(item)}catch{workspace.issue=error.localizedDescription}}}}.padding()
            if let issue=workspace.issue {Text(issue).foregroundStyle(.red)}
        }.navigationTitle(draft.confirmed ? "个人笔记":"整理草稿").toolbar{
            ToolbarItem(placement:.cancellationAction){Button("保存"){save();if workspace.issue==nil {dismiss()}}}
            ToolbarItem(placement:.confirmationAction){Button("确认笔记"){draft.confirmed=true;save();if workspace.issue==nil {dismiss()}}}
        }.sheet(isPresented:Binding(get:{preview != nil},set:{if !$0 {preview=nil}})){if let preview{ClassroomPreview(url:preview)}}.interactiveDismissDisabled()}
    }
    private func save(){guard var lesson=workspace.lessons.first(where:{$0.id==lessonID}),let index=lesson.drafts.firstIndex(where:{$0.id==draft.id}) else{return};lesson.drafts[index]=draft;workspace.save(lesson)}
}
struct ClassroomPreview:UIViewControllerRepresentable {
    let url:URL
    func makeCoordinator()->Coordinator{Coordinator(url)}
    func makeUIViewController(context:Context)->QLPreviewController{let controller=QLPreviewController();controller.dataSource=context.coordinator;return controller}
    func updateUIViewController(_ controller:QLPreviewController,context:Context){}
    final class Coordinator:NSObject,QLPreviewControllerDataSource {
        let url:URL
        init(_ url:URL){self.url=url}
        func numberOfPreviewItems(in controller:QLPreviewController)->Int{1}
        func previewController(_ controller:QLPreviewController,previewItemAt index:Int)->QLPreviewItem{url as NSURL}
    }
}
