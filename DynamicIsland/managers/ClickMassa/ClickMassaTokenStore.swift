//
//  ClickMassaTokenStore.swift
//  DynamicIsland
//
//  Keychain storage for the ClickMassa credentials and session token.
//

import Foundation
import Security

/// The ClickMassa credentials, kept in the Keychain rather than in `Defaults`.
///
/// Three items, the same shape as ``MattermostTokenStore``. The password is held
/// because a ClickMassa session lasts about eight hours -- the JWT's own `exp`
/// minus `iat` -- so signing in again from it is the only way this keeps working
/// from one day to the next without asking.
final class ClickMassaTokenStore: @unchecked Sendable {
    static let shared = ClickMassaTokenStore()

    private static let service = "com.Ebullioscopic.Atoll.ClickMassa"

    private enum Account {
        static let email = "email"
        static let password = "password"
        static let sessionToken = "sessionToken"
    }

    private let lock = NSLock()
    private var cachedEmail: String?
    private var cachedPassword: String?
    private var cachedToken: String?

    private init() {
        cachedEmail = Self.read(account: Account.email)
        cachedPassword = Self.read(account: Account.password)
        cachedToken = Self.read(account: Account.sessionToken)
    }

    // MARK: - Credentials

    var email: String {
        lock.lock(); defer { lock.unlock() }
        return cachedEmail ?? ""
    }

    var password: String {
        lock.lock(); defer { lock.unlock() }
        return cachedPassword ?? ""
    }

    var hasCredentials: Bool {
        !email.isEmpty && !password.isEmpty
    }

    func setCredentials(email: String, password: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        cachedEmail = trimmedEmail.isEmpty ? nil : trimmedEmail
        cachedPassword = password.isEmpty ? nil : password
        lock.unlock()

        Self.write(trimmedEmail, account: Account.email)
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

    func clear() {
        lock.lock()
        cachedEmail = nil
        cachedPassword = nil
        cachedToken = nil
        lock.unlock()

        Self.delete(account: Account.email)
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

    @discardableResult
    private static func write(_ value: String, account: String) -> OSStatus {
        guard !value.isEmpty else { return delete(account: account) }

        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }

        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    @discardableResult
    private static func delete(account: String) -> OSStatus {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
