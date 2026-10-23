import Foundation
import Security

enum KeychainStore {
    private static let service = AppViewModel.demoMode ? "com.tangenix.podtrackio.demo" : "com.tangenix.podtrackio"
    private static let groqAccount = "groq-api-key"
    private static let transcriptAPIAccount = "transcriptapi-api-key"
    private static let authAccessTokenAccount = "supabase-access-token"
    private static let authRefreshTokenAccount = "supabase-refresh-token"

    /// Keychain reads can block (and prompt on re-signed builds); read the Groq key once and cache it.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedGroqKey: String??

    static func saveGroqAPIKey(_ key: String) throws {
        defer { cacheLock.withLock { cachedGroqKey = nil } }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw KeychainError.emptyValue }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: groqAccount
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func groqAPIKey() -> String? {
        if let cached = cacheLock.withLock({ cachedGroqKey }) { return cached }
        let value = readGroqAPIKey()
        cacheLock.withLock { cachedGroqKey = .some(value) }
        return value
    }

    private static func readGroqAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: groqAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func removeGroqAPIKey() throws {
        defer { cacheLock.withLock { cachedGroqKey = nil } }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: groqAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    static func saveTranscriptAPIKey(_ key: String) throws {
        try save(key, account: transcriptAPIAccount)
    }

    static func transcriptAPIKey() -> String? {
        value(account: transcriptAPIAccount)
    }

    static func removeTranscriptAPIKey() throws {
        try remove(account: transcriptAPIAccount)
    }

    static func saveAuthSession(accessToken: String, refreshToken: String) throws {
        try save(accessToken, account: authAccessTokenAccount)
        do {
            try save(refreshToken, account: authRefreshTokenAccount)
        } catch {
            try? remove(account: authAccessTokenAccount)
            throw error
        }
    }

    static func authAccessToken() -> String? {
        value(account: authAccessTokenAccount)
    }

    static func authRefreshToken() -> String? {
        value(account: authRefreshTokenAccount)
    }

    static func removeAuthSession() throws {
        try remove(account: authAccessTokenAccount)
        try remove(account: authRefreshTokenAccount)
    }

    private static func save(_ key: String, account: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw KeychainError.emptyValue }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    private static func value(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func remove(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

enum KeychainError: LocalizedError {
    case emptyValue
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyValue: "Enter a Groq API key first."
        case .status(let status): "Keychain returned error \(status)."
        }
    }
}
