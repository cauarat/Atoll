//
//  MattermostTokenStore.swift
//  DynamicIsland
//
//  Keychain storage for the Mattermost personal access token.
//

import Foundation
import Security

/// The Mattermost personal access token, kept in the Keychain rather than in
/// `Defaults`.
///
/// It is a full-account credential: anything holding it can read and post as the
/// user. The `Defaults` backend is a preferences plist that any process running
/// as the user can read, so the Cider and Spotify tokens already live here for
/// the same reason. Never log it.
final class MattermostTokenStore: @unchecked Sendable {
    static let shared = MattermostTokenStore()

    private static let service = "com.Ebullioscopic.Atoll.Mattermost"
    private static let account = "personalAccessToken"

    private let lock = NSLock()
    private var cached: String?

    private init() {
        cached = Self.readFromKeychain()
    }

    var token: String {
        lock.lock()
        defer { lock.unlock() }
        return cached ?? ""
    }

    var hasToken: Bool {
        !token.isEmpty
    }

    /// Writing an empty string removes the item rather than storing a blank one,
    /// so clearing the field in settings actually forgets the token.
    func setToken(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        cached = trimmed.isEmpty ? nil : trimmed
        lock.unlock()

        if trimmed.isEmpty {
            Self.deleteFromKeychain()
        } else {
            Self.writeToKeychain(trimmed)
        }
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readFromKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    @discardableResult
    private static func writeToKeychain(_ value: String) -> OSStatus {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    @discardableResult
    private static func deleteFromKeychain() -> OSStatus {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
