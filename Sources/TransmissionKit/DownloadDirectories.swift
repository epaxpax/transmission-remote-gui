import Foundation

/// Per-server download-directory choices for the Add dialog: favorites the user pinned and the
/// most recently used destinations. These are daemon-side paths (never local Finder paths), so
/// they are only trimmed and compared as text — no file-system lookups.
public struct DownloadDirectories: Codable, Hashable, Sendable {
    /// How many recently used directories are kept.
    public static let recentLimit = 10

    public private(set) var favorites: [String]
    /// Most recent first.
    public private(set) var recent: [String]

    public init(favorites: [String] = [], recent: [String] = []) {
        self.favorites = Self.deduplicated(favorites)
        self.recent = Array(Self.deduplicated(recent).prefix(Self.recentLimit))
    }

    public var isEmpty: Bool { favorites.isEmpty && recent.isEmpty }

    /// Moves `path` to the front of the history (deduplicated, capped at `recentLimit`).
    public mutating func recordUsed(_ path: String) {
        guard let path = Self.normalized(path) else { return }
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    }

    public func isFavorite(_ path: String) -> Bool {
        guard let path = Self.normalized(path) else { return false }
        return favorites.contains(path)
    }

    /// Appends `path` to the favorites unless it is already there.
    public mutating func addFavorite(_ path: String) {
        guard let path = Self.normalized(path), !favorites.contains(path) else { return }
        favorites.append(path)
    }

    public mutating func removeFavorite(_ path: String) {
        guard let path = Self.normalized(path) else { return }
        favorites.removeAll { $0 == path }
    }

    public mutating func clearRecent() {
        recent = []
    }

    /// The `download-dir` to send with `torrent-add`: `nil` when the field is empty or names the
    /// daemon's default directory, so the daemon keeps applying its own default.
    public static func effectiveDownloadDir(_ field: String, daemonDefault: String?) -> String? {
        guard let path = normalized(field) else { return nil }
        if let daemonDefault, normalized(daemonDefault) == path { return nil }
        return path
    }

    /// Trimmed path without trailing separators (a bare root such as `/` or `C:\` is kept);
    /// `nil` when nothing is left.
    public static func normalized(_ raw: String) -> String? {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.count > 1, let last = path.last, last == "/" || last == "\\" {
            let rest = path.dropLast()
            if rest.count == 2, rest.last == ":", rest.first?.isLetter == true { break }   // C:\
            path = String(rest)
        }
        return path.isEmpty ? nil : path
    }

    private static func deduplicated(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap(normalized).filter { seen.insert($0).inserted }
    }

    // Decoding goes through `init` so a hand-edited file is normalized and capped as well.
    private enum CodingKeys: String, CodingKey { case favorites, recent }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(favorites: try container.decodeIfPresent([String].self, forKey: .favorites) ?? [],
                  recent: try container.decodeIfPresent([String].self, forKey: .recent) ?? [])
    }
}
