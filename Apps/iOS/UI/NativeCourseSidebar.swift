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
    var body:some View {
        List {
            Button("课程仓库",systemImage:"books.vertical",action:onCourses)
            if let onStudies { Button("本地讲解",systemImage:"tray.full",action:onStudies) }
            if !query.isEmpty {
                if let issue { Text(issue).foregroundStyle(.secondary) }
                else if reader.state?.searchStatus == "error" { Text("搜索索引加载失败，请刷新课程。").foregroundStyle(.secondary) }
                else if reader.state?.searchStatus != "ready" { ProgressView("加载搜索索引") }
                else if results.isEmpty { Text("没有匹配的内容").foregroundStyle(.secondary) }
                ForEach(results) { result in
                    Button { onOpen(result.target) } label: {
                        VStack(alignment:.leading,spacing:4) {
                            Text(result.title).lineLimit(2)
                            if let snippet=result.snippet { Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                        }
                    }
                }
            } else if let index {
                let pinned=index.items.filter{(reader.state?.pinnedKeys ?? []).contains($0.id)}
                if !pinned.isEmpty {
                    Section("置顶") { ForEach(pinned) { item in CourseDocumentRow(item:item,reader:reader,onOpen:onOpen) } }
                }
                ForEach(snapshot.course.manifest.sections.indices,id:\.self) { position in
                    let section=snapshot.course.manifest.sections[position]
                    Section(section.title) {
                        ForEach(expansion.rows(index.tree(kind:section.kind,sectionRoot:section.path))) { row in
                            Group {
                                if let item=row.node.item { CourseDocumentRow(item:item,reader:reader,onOpen:onOpen) }
                                else {
                                    Button { expansion.toggle(row.id) } label: {
                                        HStack(spacing:8) {
                                            Image(systemName:expansion.expandedIDs.contains(row.id) ? "chevron.down":"chevron.right")
                                                .font(.caption).frame(width:14)
                                            Label(row.node.label,systemImage:"folder").lineLimit(2)
                                        }.foregroundStyle(.primary)
                                    }.accessibilityValue(expansion.expandedIDs.contains(row.id) ? "已展开":"已收起")
                                }
                            }.padding(.leading,CGFloat(row.depth)*16)
                        }
                    }
                }
            } else if let issue { Text(issue).foregroundStyle(.secondary) }
        }
        .listStyle(.sidebar)
        .navigationTitle("课程目录")
        .searchable(text:$query,prompt:"搜索课程正文")
        .task(id:snapshot.id) {
            do {
                guard let data=snapshot.course.indices["index.json"] else { throw ReaderError.invalidIndex }
                let loaded=try CourseNavigationIndex(data:data)
                index=loaded
                if let kind=reader.state?.documentKind.flatMap(DocumentKind.init(rawValue:)),let path=reader.state?.path {
                    for section in snapshot.course.manifest.sections {
                        expansion.reveal(.init(kind:kind,path:path),in:loaded.tree(kind:section.kind,sectionRoot:section.path))
                    }
                }
            } catch { issue=error.localizedDescription }
        }
        .onChange(of:(reader.state?.documentKind ?? "")+":"+(reader.state?.path ?? "")) {
            guard let index,let kind=reader.state?.documentKind.flatMap(DocumentKind.init(rawValue:)),let path=reader.state?.path else {return}
            for section in snapshot.course.manifest.sections {
                expansion.reveal(.init(kind:kind,path:path),in:index.tree(kind:section.kind,sectionRoot:section.path))
            }
        }
        .task(id:query+":"+(reader.state?.searchStatus ?? "")) {
            guard !query.isEmpty, reader.state?.searchStatus == "ready" else { results=[];return }
            let requested=query
            do {
                let found=try await reader.searchNative(requested)
                if !Task.isCancelled && query==requested { results=found;issue=nil }
            } catch { if !Task.isCancelled { issue=error.localizedDescription } }
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
