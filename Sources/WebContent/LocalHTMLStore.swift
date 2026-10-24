import Foundation

public struct HTMLDocument: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let entry: String
    public var openedAt: Date
    public var name: String { URL(fileURLWithPath: entry).lastPathComponent }
}

public struct HTMLImportDraft: Identifiable, Sendable {
    public let id: UUID
    public let directory: URL
    public let entries: [String]
}

public enum LocalHTMLError: LocalizedError {
    case noHTML, invalidFile, unavailable
    case invalidDraft(String)
    public var errorDescription: String? {
        switch self {
        case .noHTML: return "所选文件夹中没有 HTML 文件。"
        case .invalidFile: return "请选择 HTML/HTM 文件或完整网页文件夹，文件不能包含符号链接。"
        case .invalidDraft(let detail): return "网页导入记录无效。\n" + detail
        case .unavailable: return "无法读取所选文件，请确认文件已下载并重新选择。"
        }
    }
}

public struct LocalHTMLStore: Sendable {
    public let directory: URL
    private var recordURL: URL { directory.appendingPathComponent("recent.json") }

    public init(directory: URL) { self.directory = directory.standardizedFileURL.resolvingSymlinksInPath() }

    public func recent() throws -> HTMLDocument? {
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
        let document = try JSONDecoder().decode(HTMLDocument.self, from: Data(contentsOf: recordURL))
        _ = try fileURL(for: document)
        return document
    }

    public func prepare(source: URL) throws -> HTMLImportDraft {
        try Task.checkCancellation()
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw LocalHTMLError.invalidFile }
        let id = UUID()
        let staging = directory.appendingPathComponent(".staging-" + id.uuidString)
        let content = staging.appendingPathComponent("content")
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: staging) } }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        if values.isDirectory == true {
            try FileManager.default.copyItem(at: source, to: content)
        } else {
            guard values.isRegularFile == true, ["html", "htm"].contains(source.pathExtension.lowercased()) else { throw LocalHTMLError.invalidFile }
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: content.appendingPathComponent(source.lastPathComponent))
        }
        let canonicalContent = content.standardizedFileURL.resolvingSymlinksInPath()
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: canonicalContent, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey], errorHandler: { _, error in enumerationError = error; return false }) else { throw LocalHTMLError.unavailable }
        var entries: [String] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let item = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard item.isSymbolicLink != true else { throw LocalHTMLError.invalidFile }
            if item.isRegularFile == true, ["html", "htm"].contains(url.pathExtension.lowercased()) {
                let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
                guard components.starts(with: canonicalContent.pathComponents) else { throw LocalHTMLError.invalidFile }
                let path = components.dropFirst(canonicalContent.pathComponents.count).joined(separator: "/")
                guard Self.valid(path) else { throw LocalHTMLError.invalidFile }
                entries.append(path)
            }
        }
        if let enumerationError { throw enumerationError }
        guard !entries.isEmpty else { throw LocalHTMLError.noHTML }
        entries.sort {
            let a = ["index.html", "index.htm"].firstIndex(of: $0.lowercased()) ?? 2
            let b = ["index.html", "index.htm"].firstIndex(of: $1.lowercased()) ?? 2
            return a == b ? $0.localizedStandardCompare($1) == .orderedAscending : a < b
        }
        try Task.checkCancellation()
        retained = true
        return HTMLImportDraft(id: id, directory: staging, entries: entries)
    }

    public func accept(_ draft: HTMLImportDraft, entry: String) throws -> HTMLDocument {
        let staging = try stagingDirectory(for: draft)
        guard draft.entries.contains(entry), Self.valid(entry) else { throw LocalHTMLError.invalidDraft("所选入口不属于当前导入：" + entry) }
        let previous = try recent()
        let document = HTMLDocument(id: draft.id, entry: entry, openedAt: Date())
        let destination = rootURL(for: document).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staging, to: destination)
        do {
            _ = try fileURL(for: document)
            try JSONEncoder().encode(document).write(to: recordURL, options: .atomic)
        } catch {
            let original = error
            do { try FileManager.default.moveItem(at: destination, to: staging) }
            catch { throw LocalHTMLError.invalidDraft("恢复暂存目录失败。\n" + original.localizedDescription + "\n" + error.localizedDescription) }
            throw original
        }
        if let previous { try? FileManager.default.removeItem(at: rootURL(for: previous).deletingLastPathComponent()) }
        return document
    }

    public func markOpened(_ document: HTMLDocument) throws -> HTMLDocument {
        guard try recent()?.id == document.id else { throw LocalHTMLError.invalidDraft("最近阅读记录与当前文件不一致。") }
        var updated = document
        updated.openedAt = Date()
        try JSONEncoder().encode(updated).write(to: recordURL, options: .atomic)
        return updated
    }

    public func discard(_ draft: HTMLImportDraft) throws {
        try FileManager.default.removeItem(at: stagingDirectory(for: draft))
    }

    public func clear() throws {
        guard let document = try recent() else { return }
        try FileManager.default.removeItem(at: recordURL)
        try FileManager.default.removeItem(at: rootURL(for: document).deletingLastPathComponent())
    }

    public func rootURL(for document: HTMLDocument) -> URL {
        directory.appendingPathComponent("imports/" + document.id.uuidString + "/content")
    }

    public func fileURL(for document: HTMLDocument) throws -> URL {
        guard Self.valid(document.entry) else { throw LocalHTMLError.invalidFile }
        let root = rootURL(for: document).resolvingSymlinksInPath()
        let file = root.appendingPathComponent(document.entry).standardizedFileURL
        guard file.resolvingSymlinksInPath().pathComponents.starts(with: root.pathComponents), try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw LocalHTMLError.unavailable }
        return file
    }

    private func stagingDirectory(for draft: HTMLImportDraft) throws -> URL {
        let library = directory.standardizedFileURL.resolvingSymlinksInPath()
        let expected = library.appendingPathComponent(".staging-" + draft.id.uuidString, isDirectory: true)
        let actual = draft.directory.standardizedFileURL.resolvingSymlinksInPath()
        guard actual.pathComponents == expected.pathComponents else {
            throw LocalHTMLError.invalidDraft("暂存目录身份不匹配。\n实际：" + actual.path + "\n预期：" + expected.path)
        }
        let values = try expected.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw LocalHTMLError.invalidDraft("暂存目录不存在或不是实体目录。") }
        return expected
    }

    private static func valid(_ path: String) -> Bool {
        !path.isEmpty && !path.contains("\\") && !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
