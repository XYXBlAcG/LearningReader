import Foundation
import ZIPFoundation

public struct CourseSnapshot: Identifiable, Sendable {
    public let revision: String
    public let root: URL
    public let course: IndexedCourse
    public let derived: URL
    public var id: String { root.path + ":" + revision }

    public func resource(path: String) throws -> URL {
        guard let decoded = path.removingPercentEncoding else { throw ReaderError.invalidPath }
        let relative = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
        guard CoursePath.valid(relative) else { throw ReaderError.invalidPath }
        if relative == "reader/config.js" { return try CoursePath.file("config.js", in: derived) }
        if relative == "reader/document-paths.json" { return try CoursePath.file("document-paths.json", in: derived) }
        if relative.hasPrefix("reader/") { return try CoursePath.file(String(relative.dropFirst(7)), in: ReaderAssets.reader) }
        if ["content/index.json", "content/graph.json", "content/search-index.json", "content/glossary.json"].contains(relative) { return try CoursePath.file(String(relative.dropFirst(8)), in: derived) }
        for kind in [DocumentKind.note, .exercise] {
            let prefix = "content/" + kind.rawValue + "/"
            if relative.hasPrefix(prefix) {
                let file = String(relative.dropFirst(prefix.count))
                guard course.documents.contains(where: { $0.kind == kind && $0.path == file }) else { throw ReaderError.invalidPath }
                return try CoursePath.file(file, in: course.root)
            }
        }
        if relative.hasPrefix("media/") {
            let file = String(relative.dropFirst(6))
            guard course.media.contains(file) else { throw ReaderError.invalidPath }
            return try CoursePath.file(file, in: course.root)
        }
        throw ReaderError.invalidPath
    }
}

public final class SnapshotStore: @unchecked Sendable {
    private static let installationLock = NSLock()
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func current() throws -> CourseSnapshot? {
        let pointer = directory.appendingPathComponent("current.json")
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        let record = try JSONDecoder().decode(SnapshotRecord.self, from: Data(contentsOf: pointer))
        guard Self.validRevision(record.revision) else { throw ReaderError.invalidSnapshot }
        let root = directory.appendingPathComponent("versions/" + record.revision)
        let course = try CourseIndexer.build(root: root.appendingPathComponent("Repository"), configuration: record.configuration)
        let derived = root.appendingPathComponent("Derived")
        try Self.writeDerived(course: course, to: derived)
        return CourseSnapshot(revision: record.revision, root: root, course: course, derived: derived)
    }

    public func install(archive: URL, revision: String, configuration: ImportConfiguration) throws -> CourseSnapshot {
        Self.installationLock.lock()
        defer { Self.installationLock.unlock() }
        try Task.checkCancellation()
        guard Self.validRevision(revision) else { throw ReaderError.invalidSnapshot }
        let zip = try Archive(url: archive, accessMode: .read)
        var roots = Set<String>(), names = Set<String>(), total: UInt64 = 0
        for entry in zip {
            let path = entry.type == .directory ? String(entry.path.dropLast()) : entry.path
            guard CoursePath.valid(path), entry.type != .symlink, names.insert(entry.path).inserted, names.count <= 50_000 else { throw ReaderError.invalidSnapshot }
            roots.insert(String(path.split(separator: "/")[0]))
            total += UInt64(entry.uncompressedSize)
            guard total <= 512 * 1024 * 1024 else { throw ReaderError.course("解压后课程超过 512 MB，请选择较小的课程仓库。") }
        }
        guard roots.count == 1, let rootName = roots.first else { throw ReaderError.invalidSnapshot }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent("staging-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.unzipItem(at: archive, to: staging)
        let repository = staging.appendingPathComponent(rootName)
        let course = try CourseIndexer.build(root: repository, configuration: configuration)
        let derived = staging.appendingPathComponent("Derived")
        try Self.writeDerived(course: course, to: derived)
        let versions = directory.appendingPathComponent("versions")
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        let destination = versions.appendingPathComponent(revision)
        let previous = try current()?.revision
        if !FileManager.default.fileExists(atPath: destination.path) {
            let prepared = staging.appendingPathComponent("prepared")
            try FileManager.default.createDirectory(at: prepared, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: repository, to: prepared.appendingPathComponent("Repository"))
            try FileManager.default.moveItem(at: derived, to: prepared.appendingPathComponent("Derived"))
            try FileManager.default.moveItem(at: prepared, to: destination)
        }
        let record = SnapshotRecord(revision: revision, configuration: configuration)
        try Task.checkCancellation()
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("current.json"), options: .atomic)
        let keep = Set([revision, previous].compactMap { $0 })
        for cached in try FileManager.default.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil) where Self.validRevision(cached.lastPathComponent) && !keep.contains(cached.lastPathComponent) {
            try? FileManager.default.removeItem(at: cached)
        }
        guard let installed = try current() else { throw ReaderError.invalidSnapshot }
        return installed
    }

    public func openLocal(root: URL, configuration: ImportConfiguration) throws -> CourseSnapshot {
        Self.installationLock.lock()
        defer { Self.installationLock.unlock() }
        try Task.checkCancellation()
        let course = try CourseIndexer.build(root: root, configuration: configuration)
        try Task.checkCancellation()
        let derived = directory.appendingPathComponent("local-derived")
        try Self.writeDerived(course: course, to: derived)
        return .init(revision: UUID().uuidString, root: root, course: course, derived: derived)
    }

    private static func validRevision(_ value: String) -> Bool { value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil }

    private static func writeDerived(course: IndexedCourse, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in course.indices { try data.write(to: directory.appendingPathComponent(name), options: .atomic) }
        try course.redirects.write(to: directory.appendingPathComponent("document-paths.json"), options: .atomic)
        let config: [String: Any] = ["title": course.manifest.title, "entry": course.manifest.entry, "sections": course.manifest.sections.map { ["kind": $0.kind.rawValue, "path": $0.path, "title": $0.title] }]
        let json = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        let script = "window.READER_DATA_MODE='static';window.COURSE=" + String(decoding: json, as: UTF8.self) + ";"
        try Data(script.utf8).write(to: directory.appendingPathComponent("config.js"), options: .atomic)
    }
}

private struct SnapshotRecord: Codable {
    let revision: String
    let configuration: ImportConfiguration
}

public struct CourseLibrary: Codable, Sendable {
    public var sources: [CourseSource] = []
    public var selectedID: String?
    public init() {}
    public static func read(at url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public func save(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
