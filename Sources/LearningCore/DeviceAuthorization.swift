import Foundation

public struct GitHubCredential: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let clientID: String
    public var login: String?
}

public struct DeviceChallenge: Decodable, Sendable {
    public let device_code: String
    public let user_code: String
    public let verification_uri: URL
    public let expires_in: Int
    public let interval: Int
}

public enum AuthorizationError: LocalizedError {
    case invalidClient, declined, expired, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidClient: return "请检查 GitHub App 的 Client ID，并在该应用设置中启用 Device Flow。"
        case .declined: return "你已取消 GitHub 授权。"
        case .expired: return "授权已过期，请重新登录 GitHub。"
        case .invalidResponse: return "GitHub 授权响应无效，请稍后重试。"
        }
    }
}

public final class DeviceAuthorization: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) { self.session = session ?? NetworkSession.make() }

    public func begin(clientID: String) async throws -> DeviceChallenge {
        guard clientID.range(of: "^[A-Za-z0-9._-]{6,128}$", options: .regularExpression) != nil else { throw AuthorizationError.invalidClient }
        let data = try await post(path: "/login/device/code", parameters: ["client_id": clientID])
        guard let challenge = try? JSONDecoder().decode(DeviceChallenge.self, from: data), challenge.verification_uri.scheme == "https", challenge.verification_uri.host == "github.com", challenge.expires_in > 0, challenge.interval > 0 else { throw AuthorizationError.invalidClient }
        return challenge
    }

    public func authorize(challenge: DeviceChallenge, clientID: String) async throws -> GitHubCredential {
        let deadline = Date().addingTimeInterval(TimeInterval(challenge.expires_in))
        var interval = max(5, challenge.interval)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let data = try await post(path: "/login/oauth/access_token", parameters: ["client_id": clientID, "device_code": challenge.device_code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            switch response.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5; continue
            case "access_denied": throw AuthorizationError.declined
            case "expired_token", "token_expired": throw AuthorizationError.expired
            case "incorrect_client_credentials", "device_flow_disabled": throw AuthorizationError.invalidClient
            case nil: return try response.credential(clientID: clientID)
            default: throw AuthorizationError.invalidResponse
            }
        }
        throw AuthorizationError.expired
    }

    public func refresh(_ credential: GitHubCredential) async throws -> GitHubCredential {
        guard let refreshToken = credential.refreshToken else { throw AuthorizationError.expired }
        let data = try await post(path: "/login/oauth/access_token", parameters: ["client_id": credential.clientID, "grant_type": "refresh_token", "refresh_token": refreshToken])
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard response.error == nil else { throw AuthorizationError.expired }
        var renewed = try response.credential(clientID: credential.clientID)
        renewed.login = credential.login
        return renewed
    }

    private func post(path: String, parameters: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://github.com" + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(parameters)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try NetworkSession.validate(response)
        return data
    }
}

private struct TokenResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
    let error: String?

    func credential(clientID: String) throws -> GitHubCredential {
        guard let token = access_token, !token.isEmpty else { throw AuthorizationError.invalidResponse }
        return GitHubCredential(accessToken: token, refreshToken: refresh_token, expiresAt: expires_in.map { Date().addingTimeInterval(TimeInterval($0)) }, clientID: clientID)
    }
}
