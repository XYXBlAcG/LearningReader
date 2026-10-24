import XCTest
@testable import WebContent

final class WebPageTests: XCTestCase {
    func testAddressesPreserveHostPortQueryAndFragments() throws {
        let url = try WebAddress.parse("  example.org:8443/课程?q=中文#定义 \n")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "example.org")
        XCTAssertEqual(url.port, 8443)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "中文")
        XCTAssertEqual(try WebAddress.parse("http://127.0.0.1:8080/test").scheme, "http")
        XCTAssertEqual(try WebAddress.parse("//example.org/path").host, "example.org")
        XCTAssertEqual(try WebAddress.parse("example.org/path?next=https://other.example").host, "example.org")
    }

    func testAddressesRejectUnsupportedSchemesAndMalformedHosts() {
        for value in ["", "javascript:alert(1)", "file:///etc/passwd", "ftp://example.org", "https://", "https://bad host/", "https://user:password@example.org"] {
            XCTAssertThrowsError(try WebAddress.parse(value), value)
        }
    }

    func testWebsiteNavigationStaysInsideAppAndRejectsFiles() throws {
        let source = WebPageSource.website(try WebAddress.parse("example.org"))
        XCTAssertEqual(source.navigation(to: try WebAddress.parse("https://other.example/path")), .allow)
        XCTAssertEqual(source.navigation(to: URL(fileURLWithPath: "/tmp/private.html")), .reject)
        XCTAssertEqual(source.navigation(to: URL(string: "mailto:person@example.org")!), .external)
        XCTAssertEqual(source.navigation(to: URL(string: "about:blank")!), .allow)
        XCTAssertEqual(source.navigation(to: URL(string: "custom-app:run")!), .reject)
    }

    func testLocalNavigationUsesCanonicalRootBoundary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("index.html")
        try Data("<html/>".utf8).write(to: file)
        let store = LocalHTMLStore(directory: root.appendingPathComponent("store"))
        let document = try store.accept(store.prepare(source: file), entry: "index.html")
        let importedRoot = store.rootURL(for: document)
        let source = WebPageSource.local(document, file: try store.fileURL(for: document), root: importedRoot)
        XCTAssertEqual(source.navigation(to: importedRoot.appendingPathComponent("next.html")), .allow)
        XCTAssertEqual(source.navigation(to: importedRoot.appendingPathComponent("../secret.html")), .reject)
        XCTAssertEqual(source.navigation(to: URL(fileURLWithPath: importedRoot.path + "-other/index.html")), .reject)
        XCTAssertEqual(source.navigation(to: try WebAddress.parse("https://example.org")), .allow)
    }
}
