import SwiftUI
import AICore
import StudyLibrary
import WebContent
import UniformTypeIdentifiers

struct StudyLibraryView:View {
    var courseID:String?
    var question:String?
    var source:StudySource?
    @EnvironmentObject private var library:StudyWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    @State private var allCourses=true
    @State private var selection=Set<UUID>()
    @State private var renaming:StudySummary?
    @State private var title=""
    @State private var importing=false
    @State private var exporting=false
    @State private var document:StudyDataDocument?
    private var filtered:[StudySummary] {
        library.records.filter {record in
            (allCourses || courseID==nil || record.source?.courseID==courseID)
            && (question==nil || record.questionDigest==StudySource.hash(question ?? ""))
            && (source==nil || (record.source?.courseID==source?.courseID && record.source?.path==source?.path && record.source?.anchor==source?.anchor))
            && (query.isEmpty || (record.title+record.searchText).localizedCaseInsensitiveContains(query))
        }
    }
    var body:some View {
        NavigationStack {
            List(selection:$selection) {
                if courseID != nil && source == nil { Toggle("显示全部课程",isOn:$allCourses) }
                if library.canUndo {Button("撤销删除",systemImage:"arrow.uturn.backward"){library.undo()} }
                ForEach(filtered) { record in
                    NavigationLink(value:record.id) {
                        VStack(alignment:.leading,spacing:5) {
                            Text(record.title).lineLimit(2)
                            Text(record.source.map{$0.kind=="web" ? URL(string:$0.path)?.host ?? "网页" : ($0.path as NSString).lastPathComponent} ?? "本地提问").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(record.updatedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.tag(record.id)
                    .swipeActions(edge:.leading){Button("删除",role:.destructive){library.delete([record.id])}}
                    .contextMenu {
                        Button("修改标题",systemImage:"pencil"){title=record.title;renaming=record}
                        Button("删除",systemImage:"trash",role:.destructive){library.delete([record.id])}
                    }
                }
            }
            .overlay{if filtered.isEmpty && library.issue==nil {ContentUnavailableView("暂无本地讲解",systemImage:"tray",description:Text("讲一讲生成的回答会自动保存，也可以手动保存。"))}}
            .searchable(text:$query,prompt:"搜索标题、题目和讲解")
            .navigationTitle("本地讲解")
            .navigationDestination(for:UUID.self){id in
                if let record=library.record(id) {SavedStudyView(initial:record,onSource:{source in dismiss();library.onOpenSource?(source)})}
            }
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("完成"){dismiss()}}
                ToolbarItemGroup(placement:.primaryAction){
                    EditButton()
                    Menu {
                        Button("导出全部讲解备份",systemImage:"square.and.arrow.up"){
                            if let data=library.backup(){document=StudyDataDocument(data:data);exporting=true}
                        }
                        Button("导入讲解备份",systemImage:"square.and.arrow.down"){importing=true}
                        if !selection.isEmpty {Button("删除所选讲解（\(selection.count)）",role:.destructive){library.delete(selection);selection=[]}}
                    }label:{Image(systemName:"ellipsis.circle")}
                }
            }
            .alert("修改标题",isPresented:Binding(get:{renaming != nil},set:{if !$0 {renaming=nil}})) {
                TextField("标题",text:$title)
                Button("取消",role:.cancel){renaming=nil}
                Button("保存"){if let record=renaming {library.rename(record.id,title:title)};renaming=nil}
            }
            .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"LearningReader-Study-Backup"){result in if case .failure(let error)=result {library.issue=error.localizedDescription}}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json,.zip]){result in
                do {
                    let url=try result.get();let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}}
                    library.restore(try Data(contentsOf:url,options:.mappedIfSafe))
                } catch {library.issue=error.localizedDescription}
            }
            .alert("本地讲解",isPresented:Binding(get:{library.issue != nil},set:{if !$0 {library.issue=nil}})){Button("知道了"){library.issue=nil}}message:{Text(library.issue ?? "")}
        }
    }
}

struct SavedStudyView:View {
    let initial:StudyRecord
    let onSource:(StudySource)->Void
    @EnvironmentObject private var library:StudyWorkspace
    @EnvironmentObject private var ai:AIWorkspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var interaction=AIInteraction()
    @State private var versionID:UUID?
    @State private var website:StudyWebsite?
    @State private var services=false
    @State private var exporting=false
    @State private var document:StudyDataDocument?
    @State private var contentType:UTType = .plainText
    private var record:StudyRecord {library.record(initial.id) ?? initial}
    private var version:StudyVersion? {record.versions.first(where:{$0.id==versionID}) ?? record.versions.last(where:{!$0.answer.isEmpty})}
    var body:some View {
        VStack(spacing:0) {
            if record.versions.count>1 {
                Picker("回答版本",selection:$versionID) {
                    Text("最新回答").tag(Optional<UUID>.none)
                    ForEach(Array(record.versions.enumerated()),id:\.element.id){index,item in Text("回答 \(index+1) · \(item.model)").tag(Optional(item.id))}
                }.pickerStyle(.menu)
            }
            StudyComparisonView(question:record.question,image:record.initial.image) {
                MarkdownContentView(markdown:version?.transcript ?? "",initialPosition:record.position,onPosition:{library.position(record.id,$0)})
            }.id(version?.id)
            HStack {
                Text(version?.model ?? "").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if version?.status != .complete {Text(version?.status == .stopped ? "已停止":"回答未完成").font(.caption).foregroundStyle(.secondary)}
            }.padding(.horizontal,16).padding(.vertical,8)
        }
        .navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.primaryAction){Menu {
            Button("继续追问",systemImage:"bubble.left.and.bubble.right"){services=true}.disabled(version?.status == .generating)
            if let source=record.source,!source.courseID.isEmpty {Button("返回原题",systemImage:"arrow.uturn.backward"){onSource(source)}}
            if let source=record.source,source.kind=="web" {
                Button("返回原网页",systemImage:"globe") {
                    do {website=StudyWebsite(url:try WebAddress.parse(source.path))}
                    catch {library.issue="原本地网页可能已移除，请从课程仓库重新打开或导入；保存的内容仍可阅读。"}
                }
            }
            Button("复制讲解",systemImage:"doc.on.doc"){UIPasteboard.general.string=version?.transcript}
            Button("导出 Markdown",systemImage:"square.and.arrow.up"){
                var markdown="# "+record.title+"\n\n## 题目\n\n"+record.question+"\n\n## 讲解\n\n"+(version?.transcript ?? "")
                if let image=record.initial.image {markdown="![题图](data:"+image.mimeType+";base64,"+image.data.base64EncodedString()+")\n\n"+markdown}
                document=StudyDataDocument(data:Data(markdown.utf8));contentType = UTType(importedAs:"net.daringfireball.markdown");exporting=true
            }
            Button("导出完整条目（含题图）") {
                do {if let version {document=StudyDataDocument(data:try StudyArchive.package(record,version:version));contentType = .zip;exporting=true}}
                catch{library.issue=error.localizedDescription}
            }
            Button("删除当前回答版本",role:.destructive){if let version {library.deleteVersion(record.id,version:version.id);versionID=nil;if !library.records.contains(where:{$0.id==record.id}) {dismiss()}}}
            Button("删除此条讲解",role:.destructive){library.delete([record.id]);dismiss()}
        }label:{Image(systemName:"ellipsis.circle")}}}
        .confirmationDialog("选择本次追问使用的服务（沿用已保存上下文）",isPresented:$services,titleVisibility:.visible){
            ForEach(ai.settings.profiles.filter{record.initial.image==nil || $0.supportsImages}){profile in
                Button(profile.name.isEmpty ? profile.model:profile.name){
                    do {try interaction.resume(record,profile:profile,workspace:ai,versionID:version?.id)}
                    catch{library.issue=error.localizedDescription}
                }
            }
            Button("AI 设置"){interaction.showSettings=true}
        }
        .fileExporter(isPresented:$exporting,document:document,contentType:contentType,defaultFilename:contentType == .zip ? "LearningReader-Study.zip":"LearningReader-Study.md"){result in if case .failure(let error)=result {library.issue=error.localizedDescription}}
        .alert("本地讲解",isPresented:Binding(get:{library.issue != nil},set:{if !$0 {library.issue=nil}})){Button("知道了"){library.issue=nil}}message:{Text(library.issue ?? "")}
        .fullScreenCover(item:$website){WebBrowserScreen(initialURL:$0.url)}
        .modifier(AIHost(interaction:interaction))
    }
}

private struct StudyWebsite:Identifiable { let url:URL;var id:String {url.absoluteString} }
