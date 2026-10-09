import Foundation
import Security

/// Simple Keychain store for server secrets (RPC password, client-certificate passphrase).
enum Keychain {
    /// Which secret of a server an entry holds.
    enum Slot {
        case rpcPassword
        case clientCertPassword
    }

    /// Historical service name — deliberately does not follow the app's renaming:
    /// changing it would "lose" existing users' saved passwords.
    private static let service = "hu.transwift.servers"

    /// The RPC password keeps the bare UUID as account (existing entries stay valid).
    private static func account(_ id: UUID, _ slot: Slot) -> String {
        switch slot {
        case .rpcPassword: return id.uuidString
        case .clientCertPassword: return id.uuidString + ".cert"
        }
    }

    static func setPassword(_ password: String, for id: UUID, slot: Slot = .rpcPassword) {
        let account = account(id, slot)
        // Delete the existing entry, then write the new one (idempotent upsert).
        deleteEntry(account)
        guard !password.isEmpty, let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func password(for id: UUID, slot: Slot = .rpcPassword) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(id, slot),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    /// Removes every secret of the server.
    static func delete(for id: UUID) {
        deleteEntry(account(id, .rpcPassword))
        deleteEntry(account(id, .clientCertPassword))
    }

    private static func deleteEntry(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
