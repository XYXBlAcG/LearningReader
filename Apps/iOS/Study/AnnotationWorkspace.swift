import SwiftUI
import PracticeCore
import AICore

@MainActor
final class AnnotationWorkspace:ObservableObject {
    @Published private(set) var items:[CourseAnnotation]=[]
    @Published var issue:String?
    @Published var unresolved=Set<String>()
    private var store:AnnotationStore?
    private var deleted:CourseAnnotation?
    init(){
        do {
            let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            store=try AnnotationStore(url:root.appendingPathComponent("LearningReader/Annotations/notes.json"));items=store?.items ?? []
        }catch{issue=error.localizedDescription}
    }
    func save(_ item:CourseAnnotation)->Bool {
        do {guard let store else {throw CocoaError(.fileReadUnknown)};try store.save(item);items=store.items;issue=nil;return true}
        catch{issue=error.localizedDescription;return false}
    }
    func delete(_ item:CourseAnnotation)->Bool {
        do {guard let store else {throw CocoaError(.fileReadUnknown)};try store.delete(item.id);deleted=item;items=store.items;issue=nil;return true}
        catch{issue=error.localizedDescription;return false}
    }
    func undo(){if let deleted,save(deleted){self.deleted=nil}}
    var canUndo:Bool {deleted != nil}
    func marks(courseID:String)->[[String:String]] {
        items.filter{$0.source.courseID==courseID}.map{["id":$0.id.uuidString,"path":$0.source.path,"kind":$0.source.kind,"quote":$0.quote,"color":$0.highlighted ? $0.color:"#C7CDD1","underline":$0.highlighted ? "false":"true","prefix":$0.prefix,"suffix":$0.suffix]}
    }
}

struct AnnotationEditor:View {
    @EnvironmentObject private var annotations:AnnotationWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var item:CourseAnnotation
    @State private var color:Color
    @State private var confirmedDelete=false
    init(item:CourseAnnotation){
        _item=State(initialValue:item)
        let value=UInt32(item.color.dropFirst(),radix:16) ?? 0xFFD166
        _color=State(initialValue:Color(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255))
    }
    var body:some View {
        NavigationStack {
            Form {
                Section("关联选文") {
                    TextEditor(text:$item.quote).frame(minHeight:80).accessibilityLabel("关联的原文文字")
                        .onChange(of:item.quote){ item.prefix="";item.suffix=""}
                    if annotations.unresolved.contains(item.id.uuidString){Text("原文位置尚未匹配。可将当前原文的准确文字粘贴到上方重新关联；原笔记仍保留。").font(.caption).foregroundStyle(.orange)}
                }
                Section("笔记"){TextEditor(text:$item.note).frame(minHeight:180).accessibilityLabel("笔记正文")}
                Section("高亮") {
                    Toggle("显示颜色高亮",isOn:$item.highlighted)
                    ColorPicker("高亮颜色",selection:$color,supportsOpacity:false)
                }
                if let issue=annotations.issue {Text(issue).foregroundStyle(.red)}
                if annotations.items.contains(where:{$0.id==item.id}) {Button("删除笔记与标记",role:.destructive){confirmedDelete=true}}
            }.navigationTitle("笔记与高亮").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("保存"){
                    var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
                    guard UIColor(color).getRed(&r,green:&g,blue:&b,alpha:&a) else {annotations.issue="无法读取所选颜色";return}
                    item.color=String(format:"#%02X%02X%02X",Int(min(1,max(0,r))*255),Int(min(1,max(0,g))*255),Int(min(1,max(0,b))*255));item.updatedAt=Date()
                    if annotations.save(item){dismiss()}
                }}
            }
            .confirmationDialog("删除这条笔记及其高亮？",isPresented:$confirmedDelete,titleVisibility:.visible){Button("删除",role:.destructive){if annotations.delete(item){dismiss()}}}
        }
    }
}

struct AnnotationLibraryView:View {
    @EnvironmentObject private var annotations:AnnotationWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var selected:CourseAnnotation?
    var body:some View {
        NavigationStack {
            List {
                if annotations.canUndo {Button("撤销删除"){annotations.undo()}}
                ForEach(annotations.items.sorted{$0.updatedAt>$1.updatedAt}){item in
                    Button{selected=item}label:{VStack(alignment:.leading,spacing:6){Text(item.quote).lineLimit(2).foregroundStyle(.primary);Text(item.note.isEmpty ? "高亮":item.note).font(.caption).foregroundStyle(.secondary).lineLimit(2);Text(item.source.path).font(.caption2).foregroundStyle(.secondary);if annotations.unresolved.contains(item.id.uuidString){Label("需要重新关联",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)}}}
                }
            }.navigationTitle("笔记与高亮").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}}}
            .sheet(item:$selected){AnnotationEditor(item:$0)}
        }
    }
}
