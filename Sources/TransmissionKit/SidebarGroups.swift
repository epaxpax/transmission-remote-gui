import Foundation

/// The sidebar's value-based filter groups (trackers, download folders, labels): every
/// distinct value with the number of torrents carrying it. Computed once per poll by the
/// model, never per redraw.
public enum SidebarGroups {
    public struct Entry: Hashable, Sendable {
        public let value: String
        public let count: Int
        public init(value: String, count: Int) { self.value = value; self.count = count }
    }

    /// A torrent with several trackers on the same host counts once for that host.
    public static func trackers(_ torrents: [Torrent]) -> [Entry] {
        group(torrents) { $0.trackerHosts }
    }

    public static func folders(_ torrents: [Torrent]) -> [Entry] {
        group(torrents) { folderKey($0.downloadDir).map { [$0] } ?? [] }
    }

    public static func labels(_ torrents: [Torrent]) -> [Entry] {
        group(torrents) { $0.labels ?? [] }
    }

    /// `/data/tv/` and `/data/tv` are the same folder; an empty path is no folder.
    public static func folderKey(_ dir: String?) -> String? {
        guard var dir, !dir.isEmpty else { return nil }
        while dir.count > 1, dir.hasSuffix("/") { dir.removeLast() }
        return dir
    }

    /// Short sidebar titles for folders: the last path component, or the full path where
    /// two folders would otherwise look the same (`/a/tv` and `/b/tv`).
    public static func folderTitles(_ folders: [String]) -> [String: String] {
        func last(_ path: String) -> String {
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? path : name
        }
        var seen: [String: Int] = [:]
        for f in folders { seen[last(f), default: 0] += 1 }
        return Dictionary(uniqueKeysWithValues: folders.map { ($0, seen[last($0)]! > 1 ? $0 : last($0)) })
    }

    /// Whether the torrent belongs to the given folder filter.
    public static func matchesFolder(_ torrent: Torrent, _ folder: String) -> Bool {
        folderKey(torrent.downloadDir) == folder
    }

    private static func group(_ torrents: [Torrent], _ values: (Torrent) -> [String]) -> [Entry] {
        var counts: [String: Int] = [:]
        for t in torrents {
            for v in Set(values(t)) { counts[v, default: 0] += 1 }
        }
        return counts.map { Entry(value: $0.key, count: $0.value) }
            .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }
}
