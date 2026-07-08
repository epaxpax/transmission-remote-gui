import Foundation

/// A file within the torrent (`files` array).
public struct TorrentFile: Codable, Hashable, Sendable {
    public var name: String
    public var length: Int
    public var bytesCompleted: Int

    public var progress: Double {
        guard length > 0 else { return 0 }
        return Double(bytesCompleted) / Double(length)
    }
}

/// Per-file state (`fileStats` array) — aligned by index with `files`.
public struct TorrentFileStat: Codable, Hashable, Sendable {
    public var bytesCompleted: Int
    public var wanted: Bool
    /// -1 low, 0 normal, 1 high.
    public var priority: Int
}

public extension TorrentFileStat {
    enum Priority: Int, Sendable, CaseIterable {
        case low = -1
        case normal = 0
        case high = 1
    }

    var priorityValue: Priority { Priority(rawValue: priority) ?? .normal }
}
