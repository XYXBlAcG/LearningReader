import XCTest
@testable import LearningCore

final class GitHubTests: XCTestCase {
    func testPublicMetadataUsesNoCredential() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        FixtureProtocol.response = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data("{\"id\":17,\"full_name\":\"course/ml\",\"default_branch\":\"main\",\"private\":false}".utf8))
        }
        let metadata = try await GitHubClient(session: session).metadata(repository: Repository("https://github.com/course/ml"))
        XCTAssertEqual(metadata.id, 17)
    }

    func testPrivateReadUsesCredentialAndEscapesBranch() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        FixtureProtocol.response = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "sha" })?.value, "topic/a&b")
            XCTAssertEqual(parts.queryItems?.count, 2)
            return (200, Data("[{\"sha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]".utf8))
        }
        let revision = try await GitHubClient(session: session).latestCommit(repository: Repository("course/ml"), branch: "topic/a&b", token: "fixture")
        XCTAssertEqual(revision.count, 40)
    }

    func testUnauthorizedIsReportedWithoutInventingContent() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        FixtureProtocol.response = { _ in (401, Data()) }
        do {
            _ = try await GitHubClient(session: session).metadata(repository: Repository("course/private"), token: "expired")
            XCTFail("Unauthorized request unexpectedly succeeded")
        } catch ReaderError.authorization { }
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class FixtureProtocol: URLProtocol {
    static var response: ((URLRequest) -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.response(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
