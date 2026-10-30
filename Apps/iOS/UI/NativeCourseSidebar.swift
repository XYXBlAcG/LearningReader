import SwiftUI
import LearningCore

struct NativeCourseSidebar:View {
    let snapshot:CourseSnapshot
    @ObservedObject var reader:ReaderController
    let onCourses:()->Void
    var onStudies:(()->Void)?=nil
    let onOpen:(ReaderDocumentTarget)->Void
    @State private var index:CourseNavigationIndex?
    @State private var expansion=CourseTreeExpansion()
    @State private var query=""
    @State private var results:[ReaderSearchResult]=[]
    @State private var issue:String?
    private var currentTarget:ReaderDocumentTarget? {
        guard let state=reader.state,let raw=state.documentKind,let kind=DocumentKind(rawValue:raw) else {return nil}
        return ReaderDocumentTarget(kind:kind,path:state.path)
    }
    private var searchIdentity:String {query+":"+(reader.state?.searchStatus ?? "")}
    var body:some View {
        List {
            Button("课程仓库",systemImage:"books.vertical",action:onCourses)
            if let onStudies { Button("本地讲解",systemImage:"tray.full",action:onStudies) }
            if query.isEmpty {directoryContent} else {searchContent}
        }
        .listStyle(.sidebar)
        .navigationTitle("课程目录")
        .searchable(text:$query,prompt:"搜索课程正文")
        .task(id:snapshot.id) {
            do {
                guard let data=snapshot.course.indices["index.json"] else {throw ReaderError.invalidIndex}
                index=try CourseNavigationIndex(data:data)
                revealCurrent()
            }catch {issue=error.localizedDescription}
        }
        .onChange(of:currentTarget) {_,_ in revealCurrent()}
        .task(id:searchIdentity) {
            guard !query.isEmpty,reader.state?.searchStatus == "ready" else {results=[];return}
            let requested=query
            do {
                let found=try await reader.searchNative(requested)
                if !Task.isCancelled && query==requested {results=found;issue=nil}
            }catch {if !Task.isCancelled {issue=error.localizedDescription}}
        }
    }
    @ViewBuilder private var directoryContent:some View {
        if let index {
            let pinned=index.items.filter{(reader.state?.pinnedKeys ?? []).contains($0.id)}
            if !pinned.isEmpty {
                Section("置顶") {ForEach(pinned) {item in CourseDocumentRow(item:item,reader:reader,onOpen:onOpen)}}
            }
            ForEach(snapshot.course.manifest.sections.indices,id:\.self) {position in
                let section=snapshot.course.manifest.sections[position]
                Section(section.title) {
                    CourseDirectoryRows(nodes:index.tree(kind:section.kind,sectionRoot:section.path),expansion:$expansion,reader:reader,onOpen:onOpen)
                }
            }
        }else if let issue {Text(issue).foregroundStyle(.secondary)}
    }
    @ViewBuilder private var searchContent:some View {
        if let issue {Text(issue).foregroundStyle(.secondary)}
        else if reader.state?.searchStatus == "error" {Text("搜索索引加载失败，请刷新课程。").foregroundStyle(.secondary)}
        else if reader.state?.searchStatus != "ready" {ProgressView("加载搜索索引")}
        else if results.isEmpty {Text("没有匹配的内容").foregroundStyle(.secondary)}
        ForEach(results) {result in
            Button {onOpen(result.target)} label: {
                VStack(alignment:.leading,spacing:4) {
                    Text(result.title).lineLimit(2)
                    if let snippet=result.snippet {Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)}
                }
            }
        }
    }
    private func revealCurrent() {
        guard let index,let target=currentTarget else {return}
        for section in snapshot.course.manifest.sections {
            expansion.reveal(target,in:index.tree(kind:section.kind,sectionRoot:section.path))
        }
    }
}

struct CourseDirectoryRows:View {
    let nodes:[CourseNavigationNode]
    @Binding var expansion:CourseTreeExpansion
    @ObservedObject var reader:ReaderController
    let onOpen:(ReaderDocumentTarget)->Void
    var body:some View {
        ForEach(expansion.rows(nodes)) { row in
            CourseDirectoryEntry(node:row.node,expanded:expansion.expandedIDs.contains(row.id),reader:reader,onToggle:{expansion.toggle(row.id)},onOpen:onOpen)
                .padding(.leading,CGFloat(row.depth)*16)
        }
    }
}

struct CourseDirectoryEntry:View {
    let node:CourseNavigationNode
    let expanded:Bool
    @ObservedObject var reader:ReaderController
    let onToggle:()->Void
    let onOpen:(ReaderDocumentTarget)->Void
    var body:some View {
        if let item=node.item {CourseDocumentRow(item:item,reader:reader,onOpen:onOpen)}
        else {
            Button(action:onToggle) {
                HStack(spacing:8) {
                    Image(systemName:expanded ? "chevron.down":"chevron.right").font(.caption).frame(width:14)
                    Label(node.label,systemImage:"folder").lineLimit(2)
                }.foregroundStyle(.primary)
            }.accessibilityValue(expanded ? "已展开":"已收起")
        }
    }
}

struct CourseDocumentRow:View {
    let item:CourseNavigationItem
    @ObservedObject var reader:ReaderController
    let onOpen:(ReaderDocumentTarget)->Void
    var body:some View {
        Button { onOpen(item.target) } label: {
            Label(item.label,systemImage:item.target.kind == .note ? "doc.text" : "pencil.and.list.clipboard")
                .lineLimit(2).foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .disabled(reader.state?.hasDocument != true)
        .contextMenu {
            Button((reader.state?.pinnedKeys ?? []).contains(item.id) ? "取消置顶" : "置顶",systemImage:"pin") {
                reader.send("pinDocument",payload:["kind":item.target.kind.rawValue,"path":item.target.path])
            }
        }
    }
    private var selected:Bool { reader.state?.path == item.target.path && reader.state?.documentKind == item.target.kind.rawValue }
}
