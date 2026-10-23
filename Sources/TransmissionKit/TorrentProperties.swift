import Foundation

// MARK: - Fetched state

/// The per-torrent settings the batch property editor shows and edits.
///
/// A dedicated type rather than more `Torrent` fields: the editor fetches these only when it
/// opens (never on the 5-second poll), and `peer-limit` is a hyphenated RPC key that the
/// synthesized `Torrent` decoding cannot map.
public struct TorrentProperties: Decodable, Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String?
    public var labels: [String]?
    /// KB/s; the limit only applies while the matching `*Limited` flag is on.
    public var downloadLimit: Int?
    public var downloadLimited: Bool?
    public var uploadLimit: Int?
    public var uploadLimited: Bool?
    /// Whether the session-wide (global / alternative) speed limits also apply.
    public var honorsSessionLimits: Bool?
    /// `TR_PRI_LOW` (-1), `TR_PRI_NORMAL` (0) or `TR_PRI_HIGH` (1).
    public var bandwidthPriority: Int?
    /// Maximum connected peers for this torrent.
    public var peerLimit: Int?

    public init(id: Int) {
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, labels
        case downloadLimit, downloadLimited, uploadLimit, uploadLimited
        case honorsSessionLimits, bandwidthPriority
        case peerLimit = "peer-limit"
    }

    /// `torrent-get` fields for `TorrentProperties`.
    public static let fields: [String] = [
        "id", "name", "labels",
        "downloadLimit", "downloadLimited", "uploadLimit", "uploadLimited",
        "honorsSessionLimits", "bandwidthPriority", "peer-limit",
    ]
}

// MARK: - Mixed values

/// A value across several torrents: all agree, they differ, or none reported it.
public enum MixedValue<Value: Equatable & Sendable>: Equatable, Sendable {
    case uniform(Value)
    case mixed
    /// No torrent reported the field (e.g. an older daemon without it).
    case unknown

    /// Combines the values of every torrent. A torrent missing the field while others have
    /// it makes the result `.mixed`: its real value is not known to match the others.
    public init<Item>(_ items: [Item], _ value: (Item) -> Value?) {
        let values = items.map(value)
        guard values.contains(where: { $0 != nil }) else { self = .unknown; return }
        guard let first = values.first ?? nil,
              values.allSatisfy({ $0 == first }) else { self = .mixed; return }
        self = .uniform(first)
    }

    public var uniformValue: Value? {
        if case .uniform(let value) = self { return value }
        return nil
    }

    public var isMixed: Bool { self == .mixed }
}

// MARK: - Bandwidth priority

public enum BandwidthPriority: Int, CaseIterable, Sendable {
    case low = -1
    case normal = 0
    case high = 1
}

// MARK: - Label operations

/// What the editor does with labels. Add/remove keep every other label a torrent has;
/// only `replace` overwrites the whole list.
public enum LabelEdit: Equatable, Sendable {
    case modify(add: [String], remove: [String])
    case replace([String])
}

public enum TorrentLabels {
    /// Splits comma-separated user input into labels: trimmed, empties dropped and
    /// duplicates (case-insensitive) removed. Transmission rejects a label containing a
    /// comma, so the comma can only ever be a separator.
    public static func parse(_ text: String) -> [String] {
        dedupe(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    /// The labels a torrent ends up with after `edit`. Additions go after the existing
    /// labels; matching is case-insensitive, so "movies" removes "Movies" and adding
    /// "MOVIES" next to "Movies" adds nothing.
    public static func apply(_ edit: LabelEdit, to existing: [String]) -> [String] {
        switch edit {
        case .replace(let labels):
            return dedupe(labels)
        case .modify(let add, let remove):
            let removed = Set(remove.map(key))
            let kept = existing.filter { !removed.contains(key($0)) }
            return dedupe(kept + add.filter { !removed.contains(key($0)) })
        }
    }

    /// Labels on every torrent, in the first torrent's order.
    public static func common(_ lists: [[String]]) -> [String] {
        guard let first = lists.first else { return [] }
        let rest = lists.dropFirst().map { Set($0.map(key)) }
        return dedupe(first).filter { label in rest.allSatisfy { $0.contains(key(label)) } }
    }

    /// Labels on some but not all torrents, in first-seen order.
    public static func partial(_ lists: [[String]]) -> [String] {
        let shared = Set(common(lists).map(key))
        return dedupe(lists.flatMap { $0 }).filter { !shared.contains(key($0)) }
    }

    private static func key(_ label: String) -> String { label.lowercased() }

    private static func dedupe(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        return labels.filter { !$0.isEmpty && seen.insert(key($0)).inserted }
    }
}

// MARK: - Edits

/// The fields the user explicitly changed in the batch editor. `nil` = unchanged, and an
/// unchanged field is never sent — so a mixed value is never flattened by accident.
public struct TorrentPropertyEdits: Equatable, Sendable {
    public var downloadLimited: Bool?
    public var downloadLimit: Int?
    public var uploadLimited: Bool?
    public var uploadLimit: Int?
    public var honorsSessionLimits: Bool?
    public var bandwidthPriority: BandwidthPriority?
    public var peerLimit: Int?
    public var labels: LabelEdit?

    public init() {}

    /// Largest value accepted for a KB/s limit (the daemon stores it as a 32-bit value).
    public static let maxSpeedLimit = Int(Int32.max)
    /// `peer-limit` is a 16-bit value in the daemon.
    public static let peerLimitRange = 1...Int(UInt16.max)

    /// Whether any field would be sent.
    public var isEmpty: Bool {
        downloadLimited == nil && downloadLimit == nil && uploadLimited == nil && uploadLimit == nil
            && honorsSessionLimits == nil && bandwidthPriority == nil && peerLimit == nil
            && labels.map(Self.isNoOp) ?? true
    }

    private static func isNoOp(_ edit: LabelEdit) -> Bool {
        if case .modify(let add, let remove) = edit { return add.isEmpty && remove.isEmpty }
        return false
    }

    /// Parses a KB/s field: a whole number from 0 up to `maxSpeedLimit`, or nil.
    public static func parseSpeedLimit(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)),
              (0...maxSpeedLimit).contains(value) else { return nil }
        return value
    }

    /// Parses a peer-limit field: a whole number within `peerLimitRange`, or nil.
    public static func parsePeerLimit(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)),
              peerLimitRange.contains(value) else { return nil }
        return value
    }

    /// The `torrent-set` calls that apply these edits to `torrents`.
    ///
    /// Non-label fields go out in one call for every id. `labels` replaces a torrent's whole
    /// list, so add/remove is computed per torrent and torrents ending with the same list
    /// share a call; a torrent whose labels would not change is left out entirely.
    /// When every torrent ends up with the same labels, they ride on the single call.
    ///
    /// `torrents` should be freshly fetched: label lists computed from a stale snapshot
    /// would drop a label added elsewhere in the meantime.
    public func setArgs(for torrents: [TorrentProperties]) -> [TorrentSetArgs] {
        guard !torrents.isEmpty else { return [] }
        let allIDs = torrents.map(\.id)

        var base = TorrentSetArgs(ids: Self.ids(allIDs))
        base.downloadLimited = downloadLimited
        base.downloadLimit = downloadLimit
        base.uploadLimited = uploadLimited
        base.uploadLimit = uploadLimit
        base.honorsSessionLimits = honorsSessionLimits
        base.bandwidthPriority = bandwidthPriority?.rawValue
        base.peerLimit = peerLimit
        let hasBase = downloadLimited != nil || downloadLimit != nil || uploadLimited != nil
            || uploadLimit != nil || honorsSessionLimits != nil || bandwidthPriority != nil || peerLimit != nil

        // Group torrents by their resulting label list, keeping first-seen order.
        var groups: [(labels: [String], ids: [Int])] = []
        if let labels {
            for torrent in torrents {
                let existing = torrent.labels ?? []
                let result = TorrentLabels.apply(labels, to: existing)
                guard result != existing else { continue }
                if let index = groups.firstIndex(where: { $0.labels == result }) {
                    groups[index].ids.append(torrent.id)
                } else {
                    groups.append((result, [torrent.id]))
                }
            }
        }

        if groups.count == 1, groups[0].ids == allIDs {
            base.labels = groups[0].labels
            return [base]
        }
        var calls: [TorrentSetArgs] = hasBase ? [base] : []
        for group in groups {
            var args = TorrentSetArgs(ids: Self.ids(group.ids))
            args.labels = group.labels
            calls.append(args)
        }
        return calls
    }

    private static func ids(_ ids: [Int]) -> RPCIds {
        .ids(ids.map { RPCIdentifier.id($0) })
    }
}

/// Transmission 3.00 (RPC version 16) introduced torrent labels. An unknown version is
/// treated as supported — the daemon simply ignores an argument it does not know.
public enum TorrentLabelSupport {
    public static let minimumRPCVersion = 16

    public static func isSupported(rpcVersion: Int?) -> Bool {
        (rpcVersion ?? minimumRPCVersion) >= minimumRPCVersion
    }
}
