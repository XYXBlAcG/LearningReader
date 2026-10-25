import Foundation
import Security
import LearningCore

enum Credentials {
    static let service = "chatgpt.nice114514.MathLearning.github"
    static let account = "XYXBlAcG/MathLearning"

    static func read() throws -> GitHubCredential? {
        guard let data = try KeychainStore.read(service: service, account: account) else { return nil }
        return try JSONDecoder().decode(GitHubCredential.self, from: data)
    }

    static func save(_ credential: GitHubCredential?) throws {
        try KeychainStore.save(try credential.map { try JSONEncoder().encode($0) }, service: service, account: account)
    }
}

enum KeychainStore {
    static func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialError(status: status) }
        return data
    }

    static func save(_ data: Data?, service: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError(status: status) }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw CredentialError(status: result) }
        } else if status != errSecSuccess { throw CredentialError(status: status) }
    }
}

struct CredentialError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "无法访问系统钥匙串（\(status)）。请解锁设备后重试。" }
}
