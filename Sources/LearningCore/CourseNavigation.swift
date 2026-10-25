import Foundation

public struct ReaderDocumentTarget:Codable,Hashable,Sendable,Identifiable {
    public let kind:DocumentKind
    public let path:String
    public let anchor:String
    public var id:String { kind.rawValue+":"+path+"#"+anchor }
    public init(kind:DocumentKind,path:String,anchor:String = "") { self.kind=kind;self.path=path;self.anchor=anchor }
}

public struct CourseNavigationItem:Identifiable,Sendable {
    public let target:ReaderDocumentTarget
    public let label:String
    public var id:String { target.kind.rawValue+":"+target.path }
}

public struct CourseNavigationNode:Identifiable,Sendable {
    public let id:String
    public let label:String
    public let path:String
    public let item:CourseNavigationItem?
    public let children:[CourseNavigationNode]?
}

public struct CourseNavigationIndex:Sendable {
    public let items:[CourseNavigationItem]
    private struct Entry:Decodable { let path:String;let label:String }
    private struct Files:Decodable { let notes:[Entry];let exercises:[Entry] }
    public init(data:Data) throws {
        let files=try JSONDecoder().decode(Files.self,from:data)
        let all=files.notes.map { CourseNavigationItem(target:.init(kind:.note,path:$0.path),label:$0.label) } + files.exercises.map { CourseNavigationItem(target:.init(kind:.exercise,path:$0.path),label:$0.label) }
        guard all.allSatisfy({CoursePath.valid($0.target.path)}) else { throw ReaderError.invalidPath }
        items=all
    }
    public func tree(kind:DocumentKind,sectionRoot:String) -> [CourseNavigationNode] {
        var root=sectionRoot == "." ? "" : sectionRoot.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        let selected=items.filter{$0.target.kind==kind}
        if !root.isEmpty && selected.contains(where:{!$0.target.path.hasPrefix(root+"/")}) { root="" }
        return nodes(selected,prefix:root)
    }
    private func nodes(_ items:[CourseNavigationItem],prefix:String) -> [CourseNavigationNode] {
        var folders:[String:[CourseNavigationItem]]=[:]
        var result:[CourseNavigationNode]=[]
        for item in items {
            let relative=prefix.isEmpty ? item.target.path : String(item.target.path.dropFirst(prefix.count+1))
            let parts=relative.split(separator:"/")
            if parts.count > 1 { folders[String(parts[0]),default:[]].append(item) }
            else { result.append(.init(id:item.id,label:item.label,path:item.target.path,item:item,children:nil)) }
        }
        for (name,files) in folders {
            let path=prefix.isEmpty ? name : prefix+"/"+name
            result.append(.init(id:files[0].target.kind.rawValue+":folder:"+path,label:name,path:path,item:nil,children:nodes(files,prefix:path)))
        }
        return result.sorted { ($0.path as NSString).lastPathComponent.localizedStandardCompare(($1.path as NSString).lastPathComponent) == .orderedAscending }
    }
}

public struct ReaderSearchResult:Decodable,Identifiable,Sendable {
    public let kind:DocumentKind
    public let path:String
    public let anchor:String?
    public let heading:String?
    public let documentLabel:String?
    public let snippet:String?
    public var target:ReaderDocumentTarget { .init(kind:kind,path:path,anchor:anchor ?? "") }
    public var id:String { target.id }
    public var title:String { heading.flatMap { $0.isEmpty ? nil : $0 } ?? documentLabel ?? path }
}
