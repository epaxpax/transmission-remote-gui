import Foundation

/// State of a torrent from the Transmission daemon (`torrent-get`).
///
/// `torrent-get` returns only the requested fields, so every field is optional.
/// Convenience getters provide defaults for display.
public struct Torrent: Codable, Identifiable, Hashable, Sendable {
    // Identity
    public var id: Int
    public var name: String?
    public var hashString: String?

    // State
    public var status: Int?
    public var error: Int?
    public var errorString: String?
    public var isFinished: Bool?
    public var isStalled: Bool?
    public var recheckProgress: Double?

    // Size / progress
    public var totalSize: Int?
    public var sizeWhenDone: Int?
    public var leftUntilDone: Int?
    public var percentDone: Double?
    public var uploadedEver: Int?
    public var downloadedEver: Int?
    public var uploadRatio: Double?

    // Rate / limit
    public var rateDownload: Int?
    public var rateUpload: Int?
    public var eta: Int?

    // Peers
    public var peersConnected: Int?
    public var peersSendingToUs: Int?
    public var peersGettingFromUs: Int?

    // Metadata
    public var addedDate: Int?
    public var doneDate: Int?
    public var downloadDir: String?
    public var comment: String?
    public var creator: String?
    public var labels: [String]?

    // Per-torrent speed limits (KB/s; *Limited = whether the limit is active)
    public var downloadLimit: Int?
    public var downloadLimited: Bool?
    public var uploadLimit: Int?
    public var uploadLimited: Bool?

    // For detail views
    public var files: [TorrentFile]?
    public var fileStats: [TorrentFileStat]?
    public var peers: [Peer]?
    public var trackerStats: [TrackerStat]?
    public var priorities: [Int]?
    public var wanted: [Int]?

    public init(id: Int) {
        self.id = id
    }
}

public extension Torrent {
    /// The Transmission status codes (`status` field).
    enum Status: Int, Sendable {
        case stopped = 0
        case queuedToVerify = 1
        case verifying = 2
        case queuedToDownload = 3
        case downloading = 4
        case queuedToSeed = 5
        case seeding = 6
    }

    var statusValue: Status { Status(rawValue: status ?? 0) ?? .stopped }

    /// Human-readable status text (Hungarian).
    var statusText: String {
        switch statusValue {
        case .stopped: return "Leállítva"
        case .queuedToVerify: return "Ellenőrzésre vár"
        case .verifying: return "Ellenőrzés \(Format.percent(recheckProgress ?? 0))"
        case .queuedToDownload: return "Letöltésre vár"
        case .downloading: return "Letöltés"
        case .queuedToSeed: return "Seedelésre vár"
        case .seeding: return "Seedelés"
        }
    }

    var displayName: String { name ?? "—" }

    /// Progress between 0…1. Overridden by `recheckProgress` during verification.
    var progress: Double {
        if statusValue == .verifying { return recheckProgress ?? 0 }
        return percentDone ?? 0
    }

    var hasError: Bool { (error ?? 0) != 0 }

    var connectedPeers: Int { peersConnected ?? 0 }
    var sendingPeers: Int { peersGettingFromUs ?? 0 }
    var receivingPeers: Int { peersSendingToUs ?? 0 }

    var downloadRate: Int { rateDownload ?? 0 }
    var uploadRate: Int { rateUpload ?? 0 }

    var ratio: Double { uploadRatio ?? 0 }

    var addedDateValue: Date? {
        guard let addedDate, addedDate > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(addedDate))
    }

    var doneDateValue: Date? {
        guard let doneDate, doneDate > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(doneDate))
    }

    // MARK: - Sort keys (for Table columns)
    //
    // `KeyPathComparator` expects a `Comparable` key, but the raw fields are optional
    // (and `Optional` is not `Comparable`). These getters provide non-optional,
    // sortable values with sensible defaults.

    /// Raw status code for sorting by state (0=stopped … 6=seeding).
    var statusSortKey: Int { status ?? 0 }

    /// For sorting by displayed size (size when done, otherwise total).
    var sizeSortKey: Int { sizeWhenDone ?? totalSize ?? 0 }

    /// Added date for sorting (missing = 0, goes to the end of the list ascending).
    var addedDateSortKey: Int { addedDate ?? 0 }

    /// ETA for sorting: unknown/infinite (`< 0`) should go to the end of the list.
    var etaSortKey: Int {
        let e = eta ?? -1
        return e < 0 ? Int.max : e
    }

    var isActive: Bool { downloadRate > 0 || uploadRate > 0 }

    var isPaused: Bool { statusValue == .stopped }
}
