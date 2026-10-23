import Foundation
import CryptoKit

public enum ReaderError: LocalizedError {
    case invalidRepository, invalidSnapshot, invalidPath, missingContent, authorization, unavailable(Int), invalidIndex
    case course(String)
    public var errorDescription: String? {
        switch self {
        case .invalidRepository: return "请输入 GitHub 仓库地址或 owner/repository。"
        case .invalidSnapshot: return "课程快照校验失败，已保留原有离线内容。"
        case .invalidPath: return "资源路径无效或不属于当前课程。"
        case .missingContent: return "请先添加并下载课程。"
        case .authorization: return "GitHub 授权失效或无权读取仓库，请检查登录和 GitHub App 的仓库授权。"
        case .unavailable(let code): return "GitHub 请求失败（HTTP \(code)）。离线内容仍可阅读。"
        case .invalidIndex: return "无法生成课程索引。"
        case .course(let reason): return reason
        }
    }
}

public struct Repository: Codable, Equatable, Sendable {
    public let owner: String
    public let name: String
    public var fullName: String { owner + "/" + name }
    public init(_ value: String) throws {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("https://github.com/") {
            guard let url = URL(string: raw), url.query == nil, url.fragment == nil else { throw ReaderError.invalidRepository }
            raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if raw.hasSuffix(".git") { raw.removeLast(4) }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0 != "." && $0 != ".." && $0.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil }) else { throw ReaderError.invalidRepository }
        owner = String(parts[0]); name = String(parts[1])
    }
}

public struct ImportConfiguration: Codable, Equatable, Sendable {
    public var root: String
    public var markdown: Bool
    public var excluding: [String]
    public init(root: String, markdown: Bool, excluding: [String]) { self.root = root; self.markdown = markdown; self.excluding = excluding }
    public static let standard = ImportConfiguration(root: "", markdown: false, excluding: [])
    public static func markdown(root: String, excluding: [String]) -> Self { .init(root: root, markdown: true, excluding: excluding) }
}

public struct CourseSource: Codable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public let repository: Repository?
    public let repositoryID: Int?
    public let branch: String
    public let localPath: String?
    public var configuration: ImportConfiguration
    public var isPrivate: Bool

    public static func remote(repository: Repository, repositoryID: Int, branch: String, configuration: ImportConfiguration, isPrivate: Bool = false) -> Self {
        let identity = "github:\(repositoryID):\(branch):\(configuration.root):\(configuration.markdown):\(configuration.excluding.sorted().joined(separator: "\n"))"
        return .init(id: digest(identity), title: repository.name, repository: repository, repositoryID: repositoryID, branch: branch, localPath: nil, configuration: configuration, isPrivate: isPrivate)
    }
    public static func local(_ url: URL, configuration: ImportConfiguration) -> Self {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return .init(id: digest("local:" + path + ":" + configuration.root + ":" + String(configuration.markdown) + ":" + configuration.excluding.sorted().joined(separator: "\n")), title: url.lastPathComponent, repository: nil, repositoryID: nil, branch: "", localPath: path, configuration: configuration, isPrivate: false)
    }
    private static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}

public enum CoursePath {
    public static func valid(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("\\") && !value.contains("\0") && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    public static func file(_ path: String, in root: URL) throws -> URL {
        guard valid(path) else { throw ReaderError.invalidPath }
        let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
        let url = canonical.appendingPathComponent(path).standardizedFileURL
        guard url.resolvingSymlinksInPath().path.hasPrefix(canonical.path + "/") else { throw ReaderError.invalidPath }
        var item = canonical
        for part in path.split(separator: "/") {
            item.appendPathComponent(String(part))
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ReaderError.invalidPath }
        }
        return url
    }
}

public enum ReaderAssets {
    public static var directory: URL {
        if let url = Bundle.main.url(forResource: "LearningReader_LearningCore", withExtension: "bundle"), let bundle = Bundle(url: url), let resources = bundle.url(forResource: "Resources", withExtension: nil) { return resources }
        return Bundle.module.url(forResource: "Resources", withExtension: nil)!
    }
    public static var reader: URL { directory.appendingPathComponent("Reader") }
    public static var nativeFetch: String { get throws { try String(contentsOf: directory.appendingPathComponent("native-fetch.js"), encoding: .utf8) } }
}
