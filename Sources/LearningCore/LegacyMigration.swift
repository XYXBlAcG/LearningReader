import Foundation
import ZIPFoundation

public enum LegacyMigration {
    public static let repositoryID = 1349652967
    public static func migrate(to directory: URL) throws -> CourseSource? {
        let support = directory.deletingLastPathComponent()
        let legacy = support.appendingPathComponent("MathLearning")
        let pointer = legacy.appendingPathComponent("current.json")
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        let revision = try JSONDecoder().decode(String.self, from: Data(contentsOf: pointer))
        guard revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { throw ReaderError.invalidSnapshot }
        let source = CourseSource.remote(repository: try Repository("XYXBlAcG/MathLearning"), repositoryID: repositoryID, branch: "master", configuration: .standard, isPrivate: true)
        let oldRepository = legacy.appendingPathComponent("versions/" + revision + "/Repository")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("learning-migration-" + UUID().uuidString)
        let course = temporary.appendingPathComponent("course")
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in ["数学笔记", "数学练习", "可视化", "输出规范.md"] {
            let original = oldRepository.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: original.path) { try FileManager.default.copyItem(at: original, to: course.appendingPathComponent(name)) }
        }
        let entry = "数学笔记/微积分/00-总览.md"
        let available = try CourseIndexer.files(root: course, excluding: [])
        guard let fallback = available.first(where: { $0.hasSuffix(".md") }) else { throw ReaderError.missingContent }
        let manifest = CourseManifest(schemaVersion: 1, title: "大学数学", entry: available.contains(entry) ? entry : fallback, sections: [.init(kind: .note, path: "数学笔记", title: "笔记"), .init(kind: .exercise, path: "数学练习", title: "练习")], assets: ["数学笔记", "数学练习"] + (FileManager.default.fileExists(atPath: course.appendingPathComponent("可视化").path) ? ["可视化"] : []), redirects: "redirects.json")
        try JSONEncoder().encode(manifest).write(to: course.appendingPathComponent("course.json"))
        let redirects = oldRepository.appendingPathComponent("答题系统/reader/document-paths.json")
        var aliases: [String: [String: String]] = [:]
        if FileManager.default.fileExists(atPath: redirects.path) {
            let old = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: redirects))
            for (kind, entries) in old {
                let prefix = kind == "note" ? "数学笔记/" : "数学练习/"
                aliases[kind] = Dictionary(uniqueKeysWithValues: entries.map { (prefix + $0.key, prefix + $0.value) })
            }
        }
        try JSONEncoder().encode(aliases).write(to: course.appendingPathComponent("redirects.json"))
        let archive = temporary.appendingPathComponent("course.zip")
        try FileManager.default.zipItem(at: course, to: archive)
        _ = try SnapshotStore(directory: directory.appendingPathComponent("courses/" + source.id)).install(archive: archive, revision: revision, configuration: .standard)
        return source
    }
}
