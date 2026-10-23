import Foundation

public final class GitHubClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) { self.session = session ?? NetworkSession.make() }

    public func latestCommit(repository: Repository, branch: String = "", token: String? = nil) async throws -> String {
        struct Commit: Decodable { let sha: String }
        let request = try request(path: "/repos/" + repository.fullName + "/commits?per_page=1" + (branch.isEmpty ? "" : "&sha=" + branch.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!), token: token)
        let (data, response) = try await session.data(for: request)
        try NetworkSession.validate(response)
        let commits = try JSONDecoder().decode([Commit].self, from: data)
        guard let sha = commits.first?.sha, sha.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { throw ReaderError.invalidSnapshot }
        return sha
    }

    public struct Metadata: Decodable, Sendable {
        public let id: Int
        public let full_name: String
        public let default_branch: String
        public let `private`: Bool
    }

    public func metadata(repository: Repository, token: String? = nil) async throws -> Metadata {
        let (data, response) = try await session.data(for: request(path: "/repos/" + repository.fullName, token: token))
        try NetworkSession.validate(response)
        return try JSONDecoder().decode(Metadata.self, from: data)
    }

    public func login(token: String) async throws -> String {
        struct User: Decodable { let login: String }
        let (data, response) = try await session.data(for: request(path: "/user", token: token))
        try NetworkSession.validate(response)
        return try JSONDecoder().decode(User.self, from: data).login
    }

    public func download(revision: String, repository: Repository, token: String? = nil) async throws -> URL {
        guard revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { throw ReaderError.invalidSnapshot }
        let request = try request(path: "/repos/" + repository.fullName + "/zipball/" + revision, token: token)
        let (url, response) = try await session.download(for: request)
        do {
            try NetworkSession.validate(response)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 128 * 1024 * 1024 else { throw ReaderError.invalidSnapshot }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func request(path: String, token: String?) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        if let token, !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LearningReader", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        return request
    }
}

enum NetworkSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: DownloadRedirects(), delegateQueue: nil)
    }

    static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw ReaderError.unavailable(0) }
        switch response.statusCode {
        case 200...299: return
        case 401, 403: throw ReaderError.authorization
        default: throw ReaderError.unavailable(response.statusCode)
        }
    }
}

private final class DownloadRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { completionHandler(nil); return }
        var redirected = request
        if request.url?.host != "api.github.com" { redirected.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(redirected)
    }
}
