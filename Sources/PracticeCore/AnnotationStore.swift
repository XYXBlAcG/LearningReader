import Foundation
import AICore

public struct CourseAnnotation:Codable,Identifiable,Sendable {
    public var id=UUID()
    public var source:StudySource
    public var quote:String
    public var prefix:String
    public var suffix:String
    public var note=""
    public var color:String
    public var highlighted=true
    public var updatedAt=Date()
    public init(source:StudySource,quote:String,color:String="#FFD166",prefix:String="",suffix:String="") {
        self.source=source;self.quote=quote;self.color=color;self.prefix=prefix;self.suffix=suffix
    }
}
public enum AnnotationError:LocalizedError {
    case invalidColor,emptyQuote,missingCourse,invalidSource
    public var errorDescription:String? {
        switch self {case .invalidColor:return "请选择有效的高亮颜色。";case .emptyQuote:return "关联选文不能为空。";case .missingCourse:return "无法确定笔记所属课程，请重新选择文字。";case .invalidSource:return "高亮仅支持课程笔记与练习。"}
    }
}
public final class AnnotationStore {
    private struct Archive:Codable {var version=1;var items:[CourseAnnotation]=[]}
    private var archive:Archive
    private let url:URL
    public var items:[CourseAnnotation] {archive.items}
    public init(url:URL) throws {
        self.url=url
        archive=FileManager.default.fileExists(atPath:url.path) ? try JSONDecoder().decode(Archive.self,from:Data(contentsOf:url)):Archive()
        guard archive.version==1 else {throw CocoaError(.fileReadCorruptFile)}
    }
    public func save(_ item:CourseAnnotation) throws {
        guard item.color.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil else {throw AnnotationError.invalidColor}
        guard !item.quote.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw AnnotationError.emptyQuote}
        guard !item.source.courseID.isEmpty else {throw AnnotationError.missingCourse}
        guard ["note","exercise"].contains(item.source.kind),!item.source.path.isEmpty else {throw AnnotationError.invalidSource}
        var next=archive
        if let index=next.items.firstIndex(where:{$0.id==item.id}) {next.items[index]=item}else{next.items.append(item)}
        try JSONEncoder().encode(next).write(to:preparedURL(),options:.atomic);archive=next
    }
    public func delete(_ id:UUID) throws {
        var next=archive;next.items.removeAll{$0.id==id}
        try JSONEncoder().encode(next).write(to:preparedURL(),options:.atomic);archive=next
    }
    private func preparedURL() throws -> URL {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);return url
    }
}
