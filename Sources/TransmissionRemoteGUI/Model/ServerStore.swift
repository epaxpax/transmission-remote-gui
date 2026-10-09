import Foundation
import TransmissionKit

/// Persists server configurations: metadata as JSON in Application Support,
/// the secrets (RPC password, client-certificate passphrase) in the Keychain.
enum ServerStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // The folder name INTENTIONALLY stays "Transwift": servers saved by earlier versions
        // live here and would be lost on rename. The user never sees it.
        let dir = base.appendingPathComponent("Transwift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("servers.json")
    }

    static func load() -> [ServerConfig] {
        guard let data = try? Data(contentsOf: fileURL),
              var servers = try? JSONDecoder().decode([ServerConfig].self, from: data) else {
            return []
        }
        // Reload the secrets from the Keychain. Versions up to 0.1.11 wrote the certificate
        // passphrase into the JSON in plain text: if one is found, move it to the Keychain
        // and rewrite the file without it.
        var migrated = false
        for index in servers.indices {
            let id = servers[index].id
            servers[index].password = Keychain.password(for: id)
            if let legacy = servers[index].clientCertPassword, !legacy.isEmpty {
                migrated = true
            } else {
                let stored = Keychain.password(for: id, slot: .clientCertPassword)
                servers[index].clientCertPassword = stored.isEmpty ? nil : stored
            }
        }
        if migrated { save(servers) }
        return servers
    }

    static func save(_ servers: [ServerConfig]) {
        // Secrets go to the Keychain; kept empty in the JSON.
        var sanitized = servers
        for index in sanitized.indices {
            let id = sanitized[index].id
            Keychain.setPassword(sanitized[index].password, for: id)
            Keychain.setPassword(sanitized[index].clientCertPassword ?? "", for: id, slot: .clientCertPassword)
            sanitized[index].password = ""
            sanitized[index].clientCertPassword = nil
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
