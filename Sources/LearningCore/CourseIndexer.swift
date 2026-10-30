import Foundation
import JavaScriptCore

public struct CourseDocument: Codable, Sendable {
    public let kind: DocumentKind
    public let path: String
    public let source: String
}

public struct IndexedCourse: Sendable {
    public let manifest: CourseManifest
    public let root: URL
    public let documents: [CourseDocument]
    public let indices: [String: Data]
    public let unresolved: [String]
    public let media: Set<String>
    public let redirects: Data
}

public enum CourseIndexer {
    public static let ignoredDirectories: Set<String> = [".git", ".github", ".build", ".obsidian", "node_modules", "build", "dist", "__pycache__", ".tmp", "venv", ".venv"]

    public static func build(root repository: URL, configuration: ImportConfiguration) throws -> IndexedCourse {
        let root: URL
        if configuration.root.isEmpty { root = repository.standardizedFileURL.resolvingSymlinksInPath() }
        else { root = try CoursePath.file(configuration.root, in: repository).standardizedFileURL.resolvingSymlinksInPath() }
        let manifestURL = root.appendingPathComponent("course.json")
        var manifest: CourseManifest
        if configuration.markdown {
            let paths = try files(root: root, excluding: configuration.excluding).filter { $0.lowercased().hasSuffix(".md") }
            guard let first = paths.first else { throw ReaderError.course("所选目录没有可阅读的 Markdown 文件。") }
            manifest = .init(schemaVersion: 1, title: root.lastPathComponent, entry: paths.contains("README.md") ? "README.md" : first, sections: [.init(kind: .note, path: ".", title: "课程")], assets: ["."], exclude: configuration.excluding)
        } else {
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw ReaderError.course("没有 course.json。请选择“按 Markdown 导入”，或按课程指南添加清单。") }
            do {
                let data = try Data(contentsOf: CoursePath.file("course.json", in: root))
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys).isSubset(of: CourseManifest.propertyNames), let sections = object["sections"] as? [[String: Any]], sections.allSatisfy({ Set($0.keys).isSubset(of: CourseSection.propertyNames) }) else { throw ReaderError.course("清单包含不支持的字段或分组。") }
                if let value = object["workflow"] {
                    guard let workflow = value as? [String: Any], Set(workflow.keys).isSubset(of: CourseWorkflow.propertyNames) else { throw ReaderError.course("本地工作流包含不支持的字段。") }
                }
                manifest = try JSONDecoder().decode(CourseManifest.self, from: data)
            }
            catch { throw ReaderError.course("course.json：" + error.localizedDescription) }
        }
        guard manifest.schemaVersion == 1, !manifest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, CoursePath.valid(manifest.entry), !manifest.sections.isEmpty, manifest.sections.count <= 2, Set(manifest.sections.map(\.kind)).count == manifest.sections.count else { throw ReaderError.course("course.json：版本、标题、入口或课程分组无效。") }
        if let workflow = manifest.workflow {
            guard !workflow.title.isEmpty, workflow.program.range(of: "^[A-Za-z][A-Za-z0-9._+-]*$", options: .regularExpression) != nil else { throw ReaderError.course("本地课程工作流名称或程序无效。") }
        }
        let exclusions = (manifest.exclude ?? []) + configuration.excluding
        guard exclusions.allSatisfy(CoursePath.valid) else { throw ReaderError.course("排除路径必须是课程根目录内的相对路径。") }
        let available = try files(root: root, excluding: exclusions)
        let availableSet = Set(available)
        guard availableSet.contains(manifest.entry), manifest.entry.lowercased().hasSuffix(".md") else { throw ReaderError.course("入口不存在或不是 Markdown：" + manifest.entry) }
        var documents: [CourseDocument] = [], seen = Set<String>(), folded = Set<String>()
        for section in manifest.sections {
            guard section.path == "." || CoursePath.valid(section.path), !section.title.isEmpty else { throw ReaderError.course("课程分组路径或标题无效。") }
            let prefix = section.path == "." ? "" : section.path + "/"
            let paths = available.filter { $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".md") }
            guard !paths.isEmpty else { throw ReaderError.course("分组没有 Markdown 文件：" + section.path) }
            for path in paths {
                try Task.checkCancellation()
                guard seen.insert(path).inserted else { throw ReaderError.course("课程分组重叠：" + path) }
                guard folded.insert(path.lowercased()).inserted else { throw ReaderError.course("课程文件大小写冲突：" + path) }
                let url = try CoursePath.file(path, in: root)
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8 * 1024 * 1024 else { throw ReaderError.course("Markdown 文件过大：" + path) }
                documents.append(.init(kind: section.kind, path: path, source: try String(contentsOf: url, encoding: .utf8)))
            }
        }
        for path in [manifest.entry] + (manifest.documents ?? []) where !seen.contains(path) {
            guard CoursePath.valid(path), availableSet.contains(path), path.lowercased().hasSuffix(".md"), folded.insert(path.lowercased()).inserted else { throw ReaderError.course("附加文章不存在或路径冲突：" + path) }
            documents.append(.init(kind: .note, path: path, source: try String(contentsOf: CoursePath.file(path, in: root), encoding: .utf8)))
            seen.insert(path)
        }
        var media = Set<String>()
        for asset in manifest.assets {
            guard asset == "." || CoursePath.valid(asset) else { throw ReaderError.invalidPath }
            let prefix = asset == "." ? "" : asset + "/"
            let matches = available.filter { ($0 == asset || $0.hasPrefix(prefix)) && !$0.lowercased().hasSuffix(".md") }
            guard !matches.isEmpty || asset == "." || FileManager.default.fileExists(atPath: root.appendingPathComponent(asset).path) else { throw ReaderError.course("资源目录不存在：" + asset) }
            media.formUnion(matches)
        }
        let script = try String(contentsOf: ReaderAssets.reader.appendingPathComponent("content-index.js"), encoding: .utf8)
        guard let context = JSContext() else { throw ReaderError.invalidIndex }
        context.evaluateScript(try String(contentsOf:ReaderAssets.reader.appendingPathComponent("checkpoint-core.js"),encoding:.utf8))
        context.evaluateScript(script)
        let input = try JSONEncoder().encode(documents)
        guard context.exception == nil, let output = context.objectForKeyedSubscript("ReaderContentIndex")?.forProperty("buildJSON")?.call(withArguments: [String(decoding: input, as: UTF8.self)])?.toString(), context.exception == nil,
              let data = output.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReaderError.course(context.exception?.toString() ?? "课程索引无效") }
        if configuration.markdown, let files = (object["files"] as? [String: Any])?["notes"] as? [[String: String]], let title = files.first(where: { $0["path"] == manifest.entry })?["label"], !title.isEmpty {
            manifest = CourseManifest(schemaVersion: 1, title: title, entry: manifest.entry, sections: manifest.sections, assets: manifest.assets, exclude: manifest.exclude)
        }
        var indices: [String: Data] = [:]
        for (key, name) in [("files", "index.json"), ("graph", "graph.json"), ("search", "search-index.json"), ("checkpoints","checkpoints.json")] {
            guard let value = object[key] else { throw ReaderError.invalidIndex }
            indices[name] = try JSONSerialization.data(withJSONObject: value)
        }
        let unresolved = ((object["graph"] as? [String: Any])?["unresolved"] as? [[String: Any]] ?? []).map { "\($0["source"] ?? "") → \($0["target"] ?? "")" }
        let redirects = try manifest.redirects.map { try Data(contentsOf: CoursePath.file($0, in: root)) } ?? Data("{\"note\":{},\"exercise\":{}}".utf8)
        _ = try JSONDecoder().decode([String: [String: String]].self, from: redirects)
        return IndexedCourse(manifest: manifest, root: root, documents: documents, indices: indices, unresolved: unresolved, media: media, redirects: redirects)
    }

    public static func files(root: URL, excluding: [String]) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { throw ReaderError.missingContent }
        var result: [String] = []
        var total = 0
        for case let url as URL in enumerator {
            let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            let fileComponents = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            guard Array(fileComponents.prefix(rootComponents.count)) == rootComponents else { throw ReaderError.invalidPath }
            let path = fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            if values.isSymbolicLink == true { throw ReaderError.course("课程不支持符号链接：" + path) }
            if ignoredDirectories.contains(url.lastPathComponent) || excluding.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true { result.append(path); total += 1 }
            guard total <= 50_000 else { throw ReaderError.course("课程文件数量超过 50000。") }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
