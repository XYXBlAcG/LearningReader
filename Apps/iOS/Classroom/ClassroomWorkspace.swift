import SwiftUI
import PDFKit
import AICore

@MainActor final class ClassroomWorkspace:ObservableObject {
    @Published private(set) var lessons:[ClassroomLesson]=[]
    @Published var issue:String?
    @Published private(set) var running:UUID?
    @Published private(set) var status=""
    private var task:Task<Void,Never>?
    private var store:ClassroomStore?
    init(){do{let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LearningReader/Classroom");let loaded=try ClassroomStore(root:root);store=loaded;lessons=loaded.lessons}catch{issue=error.localizedDescription}}
    @discardableResult func save(_ lesson:ClassroomLesson)->Bool {do{guard let store else{throw CocoaError(.fileReadUnknown)};try store.save(lesson);lessons=store.lessons;issue=nil;return true}catch{issue=error.localizedDescription;return false}}
    func delete(_ id:UUID){do{try store?.delete(id);lessons=store?.lessons ?? []}catch{issue=error.localizedDescription}}
    func file(_ item:ClassroomAttachment)throws->URL {guard let store else{throw CocoaError(.fileReadUnknown)};return try store.file(item)}
    func add(_ data:Data,name:String,kind:ClassroomAttachment.Kind,to lesson:inout ClassroomLesson)throws {
        guard let store else{throw CocoaError(.fileReadUnknown)}
        let item=try store.importData(data,name:name,kind:kind);lesson.attachments.append(item);lesson.drafts=lessons.first(where:{$0.id==lesson.id})?.drafts ?? lesson.drafts
        guard save(lesson) else{throw CocoaError(.fileWriteUnknown)}
    }
    func cancel(){task?.cancel();status="正在取消…"}
    func generate(_ lesson:ClassroomLesson,selected:Set<UUID>,firstPage:Int,lastPage:Int,ai:AIWorkspace){
        guard running==nil else{return}
        var prepared=lesson;prepared.drafts=lessons.first(where:{$0.id==lesson.id})?.drafts ?? lesson.drafts
        guard save(prepared) else{return}
        running=lesson.id;status="准备课堂资料…";issue=nil
        task=Task {
            defer{running=nil;task=nil}
            do {
                let sources=lesson.attachments.filter{selected.contains($0.id)}
                var messages=[AIMessage(role:.user,text:"课堂：\(lesson.title)\n课程章节：\(lesson.source?.title ?? "未关联")\n我的关键词：\n\(lesson.keywords)\n按来源标签 [S1 p1] 引用。关键词只代表我的速记，不得推断为老师完整原话。")]
                for (index,item) in sources.enumerated(){
                    try Task.checkCancellation()
                    let label="S\(index+1)",url=try file(item)
                    switch item.kind {
                    case .text:
                        let data=try Data(contentsOf:url)
                        guard let text=String(data:data,encoding:.utf8) else{throw AIError.generation("文本资料需为 UTF-8 编码")}
                        messages.append(.init(role:.user,text:"[\(label)] \(item.name)\n"+text))
                    case .image:
                        let image=try AIImageProcessor.prepare(data:Data(contentsOf:url))
                        guard let data=image.jpegData(compressionQuality:0.8) else{throw AIError.invalidStream}
                        messages.append(.init(role:.user,text:"[\(label) p1] \(item.name)",image:AIImage(data:data,mimeType:"image/jpeg")))
                    case .pdf:
                        guard let pdf=PDFDocument(url:url),firstPage>=1,lastPage>=firstPage,firstPage<=pdf.pageCount else{throw AIError.generation("课件页码范围无效")}
                        let end=min(lastPage,pdf.pageCount)
                        guard end-firstPage<20 else{throw AIError.generation("每次最多整理 20 页，请选择页码范围")}
                        for number in firstPage...end {
                            guard let page=pdf.page(at:number-1) else{throw AIError.invalidStream}
                            let image=page.thumbnail(of:CGSize(width:1400,height:1800),for:.mediaBox)
                            guard let data=image.jpegData(compressionQuality:0.8) else{throw AIError.invalidStream}
                            messages.append(.init(role:.user,text:"[\(label) p\(number)] \(item.name)\n"+(page.string ?? ""),image:.init(data:data,mimeType:"image/jpeg")))
                            await Task.yield();try Task.checkCancellation()
                        }
                    case .presentation:throw AIError.generation("PPT 已收集。请先转成 PDF 再选择参与 AI 整理。")
                    }
                }
                let images=messages.contains{$0.image != nil}
                guard let profile=ai.settings.profile(forImage:images) else{throw images ? AIError.imageUnsupported:AIError.configuration}
                let system="整理数学课堂资料，生成可独立阅读的 Markdown 草稿。依次给出知识结构、定义与条件、直觉、证明或例题、待解决问题、复习建议。明确区分资料内容、我的关键词、AI 补充。资料结论附 [S序号 p页码]，不可伪造出处；缺条件或无法辨认时标明待核实。没有来源支持的推导标为 AI 补充。\n"+ai.settings.teachingRules+"\n"+ai.settings.formulaRules
                let request=AIRequest(profile:profile,key:try ai.key(for:profile),system:system,messages:messages)
                status="正在思考…"
                let buffer=ClassroomOutput()
                try await AIClient().generate(request,onThinking:{},onText:{value in await buffer.set(value)})
                let output=await buffer.value
                try Task.checkCancellation()
                guard var current=lessons.first(where:{$0.id==lesson.id}) else{throw CocoaError(.fileNoSuchFile)}
                current.drafts.append(ClassroomDraft(text:output,sources:sources,keywords:lesson.keywords,model:profile.modelID))
                guard save(current) else{throw CocoaError(.fileWriteUnknown)}
                status="整理已完成，草稿待确认"
            }catch is CancellationError {status="已取消"}catch{issue=error.localizedDescription;status="整理失败，原资料已保留"}
        }
    }
}
private actor ClassroomOutput {var value="";func set(_ value:String){self.value=value}}
