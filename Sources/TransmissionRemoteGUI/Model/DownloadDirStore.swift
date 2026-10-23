import Foundation
import TransmissionKit

/// Persists the Add dialog's per-server favorite and recent download directories as JSON in
/// Application Support, keyed by server ID. Kept apart from `servers.json` so editing a server
/// (which rebuilds its `ServerConfig`) never drops the history.
enum DownloadDirStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Same folder as servers.json (see ServerStore for why it is called "Transwift").
        let dir = base.appendingPathComponent("Transwift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("download-dirs.json")
    }

    static func load() -> [UUID: DownloadDirectories] {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: DownloadDirectories].self, from: data) else {
            return [:]
        }
        var result: [UUID: DownloadDirectories] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key) { result[id] = value }
        }
        return result
    }

    static func save(_ all: [UUID: DownloadDirectories]) {
        let raw = Dictionary(uniqueKeysWithValues: all.filter { !$0.value.isEmpty }.map { ($0.key.uuidString, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(raw) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
