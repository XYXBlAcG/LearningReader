import Foundation

public enum DocumentKind: String, Codable, Sendable { case note, exercise }

public struct CourseSection: Codable, Sendable {
    public let kind: DocumentKind
    public let path: String
    public let title: String
    public static let propertyNames: Set<String> = ["kind", "path", "title"]
    public init(kind: DocumentKind, path: String, title: String) {
        self.kind = kind
        self.path = path
        self.title = title
    }
}

public struct CourseManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let title: String
    public let entry: String
    public let sections: [CourseSection]
    public let assets: [String]
    public let exclude: [String]?
    public let redirects: String?
    public static let propertyNames: Set<String> = ["schemaVersion", "title", "entry", "sections", "assets", "exclude", "redirects"]
    public init(schemaVersion: Int, title: String, entry: String, sections: [CourseSection], assets: [String], exclude: [String]? = nil, redirects: String? = nil) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.entry = entry
        self.sections = sections
        self.assets = assets
        self.exclude = exclude
        self.redirects = redirects
    }
}
