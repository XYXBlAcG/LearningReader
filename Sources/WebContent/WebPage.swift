import Foundation

public enum WebAddress {
    public static func parse(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AddressError.invalid }
        let explicitScheme = value.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        let address = value.hasPrefix("//") ? "https:" + value : (explicitScheme ? value : "https://" + value)
        guard let components = URLComponents(string: address), let url = components.url,
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              components.user == nil, components.password == nil else { throw AddressError.invalid }
        return url
    }

    public enum AddressError: LocalizedError {
        case invalid
        public var errorDescription: String? { "请输入有效的 HTTP 或 HTTPS 网址。" }
    }
}

public enum WebNavigation: Equatable, Sendable {
    case allow, external, reject
}

public enum WebPageSource: Equatable, Sendable {
    case local(HTMLDocument, file: URL, root: URL)
    case website(URL)

    public var url: URL {
        switch self {
        case .local(_, let file, _): return file
        case .website(let url): return url
        }
    }

    public var title: String {
        switch self {
        case .local(let document, _, _): return document.name
        case .website(let url): return url.host ?? "网页"
        }
    }

    public var storageID: UUID {
        switch self {
        case .local(let document, _, _): return document.id
        case .website: return UUID(uuidString: "6324FD08-8946-43BC-8484-45EF842154D1")!
        }
    }

    public func navigation(to target: URL) -> WebNavigation {
        if target.isFileURL {
            guard case .local(_, _, let root) = self else { return .reject }
            let boundary = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            let path = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            return path.starts(with: boundary) ? .allow : .reject
        }
        switch target.scheme?.lowercased() {
        case "http", "https", "about", "blob", "data", "javascript": return .allow
        case "mailto", "tel": return .external
        default: return .reject
        }
    }
}
