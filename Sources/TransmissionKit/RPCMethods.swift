import Foundation

// MARK: - Field lists

public enum TorrentFields {
    /// Fields sufficient for the list view.
    public static let list: [String] = [
        "id", "name", "hashString", "status", "error", "errorString",
        "isFinished", "isStalled", "recheckProgress",
        "totalSize", "sizeWhenDone", "leftUntilDone", "percentDone",
        "uploadedEver", "downloadedEver", "uploadRatio",
        "rateDownload", "rateUpload", "eta",
        "peersConnected", "peersSendingToUs", "peersGettingFromUs",
        "addedDate", "doneDate", "downloadDir", "labels",
    ]

    /// Additional fields needed for the detail view.
    public static let detail: [String] = list + [
        "comment", "creator",
        "files", "fileStats", "peers", "trackerStats", "priorities", "wanted",
    ]
}

// MARK: - Argument / response structs

private struct TorrentGetArgs: Encodable {
    let fields: [String]
    let ids: RPCIds?

    private enum CodingKeys: String, CodingKey { case fields, ids, format }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fields, forKey: .fields)
        try container.encode("objects", forKey: .format)
        if let ids { try container.encode(ids, forKey: .ids) }
    }
}

private struct TorrentGetResult: Decodable {
    let torrents: [Torrent]
}

private struct IDsArgs: Encodable {
    let ids: RPCIds?
    private enum CodingKeys: String, CodingKey { case ids }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let ids { try container.encode(ids, forKey: .ids) }
    }
}

private struct RemoveArgs: Encodable {
    let ids: RPCIds?
    let deleteLocalData: Bool
    private enum CodingKeys: String, CodingKey {
        case ids
        case deleteLocalData = "delete-local-data"
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let ids { try container.encode(ids, forKey: .ids) }
        try container.encode(deleteLocalData, forKey: .deleteLocalData)
    }
}

private struct TorrentAddArgs: Encodable {
    var filename: String?
    var metainfo: String?
    var paused: Bool?
    var downloadDir: String?

    private enum CodingKeys: String, CodingKey {
        case filename, metainfo, paused
        case downloadDir = "download-dir"
    }
}

public struct TorrentAddResult: Decodable, Sendable {
    public struct Added: Decodable, Sendable {
        public var id: Int?
        public var name: String?
        public var hashString: String?
    }
    public var added: Added?
    public var duplicate: Added?

    private enum CodingKeys: String, CodingKey {
        case added = "torrent-added"
        case duplicate = "torrent-duplicate"
    }

    public var isDuplicate: Bool { duplicate != nil }
}

/// `torrent-set` arguments (for file-selection / priority editing).
public struct TorrentSetArgs: Encodable, Sendable {
    public var ids: RPCIds
    public var filesWanted: [Int]?
    public var filesUnwanted: [Int]?
    public var priorityHigh: [Int]?
    public var priorityNormal: [Int]?
    public var priorityLow: [Int]?
    public var downloadLimit: Int?
    public var downloadLimited: Bool?
    public var uploadLimit: Int?
    public var uploadLimited: Bool?
    /// Sequential ("streaming") download — Transmission 4.1+. Uses snake_case
    /// (4.1 switched RPC strings to snake_case); only sent when explicitly set.
    public var sequentialDownload: Bool?

    public init(ids: RPCIds) {
        self.ids = ids
    }

    private enum CodingKeys: String, CodingKey {
        case ids
        case filesWanted = "files-wanted"
        case filesUnwanted = "files-unwanted"
        case priorityHigh = "priority-high"
        case priorityNormal = "priority-normal"
        case priorityLow = "priority-low"
        case downloadLimit = "downloadLimit"
        case downloadLimited = "downloadLimited"
        case uploadLimit = "uploadLimit"
        case uploadLimited = "uploadLimited"
        case sequentialDownload = "sequential_download"
    }
}

/// `session-set` arguments. All `Optional`: Swift's synthesized `Encodable` encodes optional
/// fields with `encodeIfPresent`, so only the settings actually set are sent.
/// (Read-only fields — version, rpc-version, blocklist-size — are not included.)
public struct SessionSetArgs: Encodable, Sendable {
    // Speed limits
    public var speedLimitDown: Int?
    public var speedLimitDownEnabled: Bool?
    public var speedLimitUp: Int?
    public var speedLimitUpEnabled: Bool?
    // Alternative speed + scheduler
    public var altSpeedDown: Int?
    public var altSpeedUp: Int?
    public var altSpeedEnabled: Bool?
    public var altSpeedTimeEnabled: Bool?
    public var altSpeedTimeBegin: Int?
    public var altSpeedTimeEnd: Int?
    public var altSpeedTimeDay: Int?
    // Peers / clients
    public var peerLimitGlobal: Int?
    public var peerLimitPerTorrent: Int?
    public var peerPort: Int?
    public var peerPortRandomOnStart: Bool?
    public var portForwardingEnabled: Bool?
    public var pexEnabled: Bool?
    public var dhtEnabled: Bool?
    public var lpdEnabled: Bool?
    public var utpEnabled: Bool?
    public var encryption: String?
    // Queues
    public var downloadQueueEnabled: Bool?
    public var downloadQueueSize: Int?
    public var seedQueueEnabled: Bool?
    public var seedQueueSize: Int?
    public var queueStalledEnabled: Bool?
    public var queueStalledMinutes: Int?
    // Download
    public var downloadDir: String?
    public var incompleteDir: String?
    public var incompleteDirEnabled: Bool?
    public var renamePartialFiles: Bool?
    public var startAddedTorrents: Bool?
    // Seeding
    public var seedRatioLimit: Double?
    public var seedRatioLimited: Bool?
    public var idleSeedingLimit: Int?
    public var idleSeedingLimitEnabled: Bool?
    // Blocklist
    public var blocklistEnabled: Bool?
    public var blocklistUrl: String?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case speedLimitDown = "speed-limit-down"
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitUp = "speed-limit-up"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeEnd = "alt-speed-time-end"
        case altSpeedTimeDay = "alt-speed-time-day"
        case peerLimitGlobal = "peer-limit-global"
        case peerLimitPerTorrent = "peer-limit-per-torrent"
        case peerPort = "peer-port"
        case peerPortRandomOnStart = "peer-port-random-on-start"
        case portForwardingEnabled = "port-forwarding-enabled"
        case pexEnabled = "pex-enabled"
        case dhtEnabled = "dht-enabled"
        case lpdEnabled = "lpd-enabled"
        case utpEnabled = "utp-enabled"
        case encryption
        case downloadQueueEnabled = "download-queue-enabled"
        case downloadQueueSize = "download-queue-size"
        case seedQueueEnabled = "seed-queue-enabled"
        case seedQueueSize = "seed-queue-size"
        case queueStalledEnabled = "queue-stalled-enabled"
        case queueStalledMinutes = "queue-stalled-minutes"
        case downloadDir = "download-dir"
        case incompleteDir = "incomplete-dir"
        case incompleteDirEnabled = "incomplete-dir-enabled"
        case renamePartialFiles = "rename-partial-files"
        case startAddedTorrents = "start-added-torrents"
        case seedRatioLimit
        case seedRatioLimited
        case idleSeedingLimit = "idle-seeding-limit"
        case idleSeedingLimitEnabled = "idle-seeding-limit-enabled"
        case blocklistEnabled = "blocklist-enabled"
        case blocklistUrl = "blocklist-url"
    }
}

/// `free-space` argument and response.
private struct FreeSpaceArgs: Encodable {
    let path: String
}

struct FreeSpaceResult: Decodable {
    let path: String?
    let sizeBytes: Int?

    private enum CodingKeys: String, CodingKey {
        case path
        case sizeBytes = "size-bytes"
    }
}

// MARK: - High-level API

public extension RPCClient {
    /// Fetches torrents with the given fields.
    func torrentGet(
        fields: [String] = TorrentFields.list,
        ids: RPCIds = .all
    ) async throws -> [Torrent] {
        let args = TorrentGetArgs(fields: fields, ids: ids.normalizedForRequest)
        let result: TorrentGetResult = try await send(method: "torrent-get", arguments: args)
        return result.torrents
    }

    func torrentStart(ids: RPCIds) async throws {
        let _: EmptyArgs = try await sendAction(method: "torrent-start", ids: ids)
    }

    func torrentStop(ids: RPCIds) async throws {
        let _: EmptyArgs = try await sendAction(method: "torrent-stop", ids: ids)
    }

    func torrentVerify(ids: RPCIds) async throws {
        let _: EmptyArgs = try await sendAction(method: "torrent-verify", ids: ids)
    }

    func torrentReannounce(ids: RPCIds) async throws {
        let _: EmptyArgs = try await sendAction(method: "torrent-reannounce", ids: ids)
    }

    func torrentRemove(ids: RPCIds, deleteLocalData: Bool) async throws {
        let args = RemoveArgs(ids: ids.normalizedForRequest, deleteLocalData: deleteLocalData)
        let _: EmptyArgs = try await send(method: "torrent-remove", arguments: args)
    }

    /// Add a torrent from a magnet link or URL (`filename`).
    @discardableResult
    func torrentAdd(filename: String, paused: Bool = false, downloadDir: String? = nil) async throws -> TorrentAddResult {
        let args = TorrentAddArgs(filename: filename, metainfo: nil, paused: paused, downloadDir: downloadDir)
        return try await send(method: "torrent-add", arguments: args)
    }

    /// Add a torrent from the contents of a `.torrent` file (base64 metainfo).
    @discardableResult
    func torrentAdd(metainfoBase64: String, paused: Bool = false, downloadDir: String? = nil) async throws -> TorrentAddResult {
        let args = TorrentAddArgs(filename: nil, metainfo: metainfoBase64, paused: paused, downloadDir: downloadDir)
        return try await send(method: "torrent-add", arguments: args)
    }

    /// Arbitrary `torrent-set` operation (file selection, priority, limits).
    func torrentSet(_ args: TorrentSetArgs) async throws {
        let _: EmptyArgs = try await send(method: "torrent-set", arguments: args)
    }

    func sessionGet() async throws -> SessionInfo {
        try await send(method: "session-get", arguments: EmptyArgs())
    }

    /// Modify global settings. Only non-nil fields are sent.
    func sessionSet(_ args: SessionSetArgs) async throws {
        let _: EmptyArgs = try await send(method: "session-set", arguments: args)
    }

    /// Free disk space in bytes at the given (daemon-side) path.
    func freeSpace(path: String) async throws -> Int {
        let result: FreeSpaceResult = try await send(method: "free-space", arguments: FreeSpaceArgs(path: path))
        return result.sizeBytes ?? 0
    }

    func sessionStats() async throws -> SessionStats {
        try await send(method: "session-stats", arguments: EmptyArgs())
    }

    private func sendAction<Response: Decodable>(method: String, ids: RPCIds) async throws -> Response {
        let args = IDsArgs(ids: ids.normalizedForRequest)
        return try await send(method: method, arguments: args)
    }
}

private extension RPCIds {
    /// For `.all` we do not send an `ids` key (applies to all torrents).
    var normalizedForRequest: RPCIds? {
        if case .all = self { return nil }
        return self
    }
}
