import Foundation
import TransmissionKit

/// Persists server configurations: metadata as JSON in Application Support,
/// the password in the Keychain.
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
        // Reload the password from the Keychain.
        for index in servers.indices {
            servers[index].password = Keychain.password(for: servers[index].id)
        }
        return servers
    }

    static func save(_ servers: [ServerConfig]) {
        // Password goes to the Keychain; kept empty in the JSON.
        var sanitized = servers
        for index in sanitized.indices {
            Keychain.setPassword(sanitized[index].password, for: sanitized[index].id)
            sanitized[index].password = ""
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
