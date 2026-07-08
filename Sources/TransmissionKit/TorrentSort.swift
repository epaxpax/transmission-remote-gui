import Foundation

/// Translates the SwiftUI `Table`'s `KeyPathComparator`s into fast, typed sorting.
///
/// `Table` requires `[KeyPathComparator<Torrent>]` for header clicks, but
/// `sorted(using:)` is orders of magnitude slower on large lists due to runtime
/// KeyPath dereferencing (measured: 2000 items, name ~57 ms/call, size ~17 ms/call).
/// Native closure-based comparison takes 0.1–9 ms instead. We match the sort key
/// against known `KeyPath`s and pick a typed closure; for unknown keys the correct
/// (though slow) `sorted(using:)` is the fallback.
public enum TorrentSort {
    public static func apply(_ items: [Torrent], _ order: [KeyPathComparator<Torrent>]) -> [Torrent] {
        guard let c = order.first else { return items }
        let asc = c.order == .forward

        func by<V: Comparable>(_ key: @escaping (Torrent) -> V) -> [Torrent] {
            items.sorted { asc ? key($0) < key($1) : key($0) > key($1) }
        }

        let kp = c.keyPath
        // Name: Finder-like natural sorting (case- and number-aware).
        if kp == \Torrent.displayName {
            return items.sorted {
                let r = $0.displayName.localizedStandardCompare($1.displayName)
                return asc ? r == .orderedAscending : r == .orderedDescending
            }
        }
        if kp == \Torrent.statusSortKey    { return by { $0.statusSortKey } }
        if kp == \Torrent.sizeSortKey      { return by { $0.sizeSortKey } }
        if kp == \Torrent.progress         { return by { $0.progress } }
        if kp == \Torrent.downloadRate     { return by { $0.downloadRate } }
        if kp == \Torrent.uploadRate       { return by { $0.uploadRate } }
        if kp == \Torrent.etaSortKey       { return by { $0.etaSortKey } }
        if kp == \Torrent.ratio            { return by { $0.ratio } }
        if kp == \Torrent.connectedPeers   { return by { $0.connectedPeers } }
        if kp == \Torrent.addedDateSortKey { return by { $0.addedDateSortKey } }

        return items.sorted(using: order) // unknown key → correct, slow fallback
    }
}
