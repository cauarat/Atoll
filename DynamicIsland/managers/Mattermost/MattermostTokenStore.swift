//
//  MattermostTokenStore.swift
//  DynamicIsland
//
//  Keychain storage for the Mattermost credentials and session token.
//

import Foundation
import Security

/// The Mattermost credentials, kept in the Keychain rather than in `Defaults`.
///
/// Three items, mirroring what mm-notify stores: the login id, the password and
/// the session token the server hands back. The password is held because a
/// Mattermost session expires after about a month, and re-logging in from it is
/// what keeps the connection alive without asking the user again.
///
/// `Defaults` is a preferences plist any process running as the user can read,
/// which is why the Cider and Spotify tokens already live here. Never log any
/// of these values.
final class MattermostTokenStore: @unchecked Sendable {
    static let shared = MattermostTokenStore()

    private static let service = "com.Ebullioscopic.Atoll.Mattermost"

    private enum Account {
        static let loginID = "loginID"
        static let password = "password"
        static let sessionToken = "sessionToken"
    }

    private let lock = NSLock()
    private var cachedLoginID: String?
    private var cachedPassword: String?
    private var cachedToken: String?

    private init() {
        cachedLoginID = Self.read(account: Account.loginID)
        cachedPassword = Self.read(account: Account.password)
        cachedToken = Self.read(account: Account.sessionToken)
    }

    // MARK: - Credentials

    var loginID: String {
        lock.lock(); defer { lock.unlock() }
        return cachedLoginID ?? ""
    }

    var password: String {
        lock.lock(); defer { lock.unlock() }
        return cachedPassword ?? ""
    }

    var hasCredentials: Bool {
        !loginID.isEmpty && !password.isEmpty
    }

    func setCredentials(loginID: String, password: String) {
        let trimmedLogin = loginID.trimmingCharacters(in: .whitespacesAndNewlines)
        // The password is taken as typed: spaces can be part of it.
        lock.lock()
        cachedLoginID = trimmedLogin.isEmpty ? nil : trimmedLogin
        cachedPassword = password.isEmpty ? nil : password
        lock.unlock()

        Self.write(trimmedLogin, account: Account.loginID)
        Self.write(password, account: Account.password)
    }

    // MARK: - Session token

    var sessionToken: String {
        lock.lock(); defer { lock.unlock() }
        return cachedToken ?? ""
    }

    func setSessionToken(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        cachedToken = trimmed.isEmpty ? nil : trimmed
        lock.unlock()

        Self.write(trimmed, account: Account.sessionToken)
    }

    /// Forgets everything. Used when the user signs out.
    func clear() {
        lock.lock()
        cachedLoginID = nil
        cachedPassword = nil
        cachedToken = nil
        lock.unlock()

        Self.delete(account: Account.loginID)
        Self.delete(account: Account.password)
        Self.delete(account: Account.sessionToken)
    }

    // MARK: - Keychain

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
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

    /// Writing an empty string removes the item rather than storing a blank one,
    /// so clearing a field in settings actually forgets it.
    @discardableResult
    private static func write(_ value: String, account: String) -> OSStatus {
        guard !value.isEmpty else { return delete(account: account) }

        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }

        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = data
        // Reconnecting has to work before the first unlock after a reboot.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    @discardableResult
    private static func delete(account: String) -> OSStatus {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
