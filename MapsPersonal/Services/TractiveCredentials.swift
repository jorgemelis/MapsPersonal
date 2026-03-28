import Foundation
import Security

// MARK: - Tractive Credentials (Keychain storage)

enum TractiveCredentials {
    private static let service = "com.jorge.mapspersonal2026.tractive"

    static var email: String? {
        get { read(account: "email") }
        set {
            if let value = newValue { save(account: "email", value: value) }
            else { delete(account: "email") }
        }
    }

    static var password: String? {
        get { read(account: "password") }
        set {
            if let value = newValue { save(account: "password", value: value) }
            else { delete(account: "password") }
        }
    }

    static var hasCredentials: Bool {
        guard let e = email, let p = password else { return false }
        return !e.isEmpty && !p.isEmpty
    }

    static func clear() {
        email = nil
        password = nil
    }

    // MARK: - Keychain helpers

    private static func save(account: String, value: String) {
        let data = Data(value.utf8)
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
