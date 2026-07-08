import Foundation

/// Encryption mode for peer connections (`encryption` field).
public enum Encryption: String, CaseIterable, Sendable {
    case required
    case preferred
    case tolerated

    /// Human-readable label (Hungarian).
    public var title: String {
        switch self {
        case .required: return "Kötelező"
        case .preferred: return "Előnyben részesített"
        case .tolerated: return "Megengedő"
        }
    }
}

/// Global session settings (`session-get` / `session-set`).
///
/// All fields are optional: `session-get` may return fields depending on the daemon
/// version, and on write we only send the fields actually modified (see `SessionSetArgs`).
public struct SessionInfo: Codable, Hashable, Sendable {
    // Daemon
    public var version: String?
    public var rpcVersion: Int?

    // Speed limits
    public var speedLimitDown: Int?
    public var speedLimitDownEnabled: Bool?
    public var speedLimitUp: Int?
    public var speedLimitUpEnabled: Bool?

    // Alternative ("turbo") speed + scheduler
    public var altSpeedDown: Int?
    public var altSpeedUp: Int?
    public var altSpeedEnabled: Bool?
    public var altSpeedTimeEnabled: Bool?
    public var altSpeedTimeBegin: Int?   // minutes from midnight
    public var altSpeedTimeEnd: Int?     // minutes from midnight
    public var altSpeedTimeDay: Int?     // bitmask (days of the week)

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
    public var blocklistSize: Int?

    /// Typed form of the `encryption` string (for a Picker).
    public var encryptionValue: Encryption {
        get { encryption.flatMap(Encryption.init(rawValue:)) ?? .preferred }
        set { encryption = newValue.rawValue }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case rpcVersion = "rpc-version"
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
        case seedRatioLimit                          // camelCase in the Transmission RPC
        case seedRatioLimited                        // camelCase in the Transmission RPC
        case idleSeedingLimit = "idle-seeding-limit"
        case idleSeedingLimitEnabled = "idle-seeding-limit-enabled"
        case blocklistEnabled = "blocklist-enabled"
        case blocklistUrl = "blocklist-url"
        case blocklistSize = "blocklist-size"
    }
}

/// Aggregate statistics (`session-stats`).
public struct SessionStats: Codable, Hashable, Sendable {
    public var activeTorrentCount: Int?
    public var pausedTorrentCount: Int?
    public var torrentCount: Int?
    public var downloadSpeed: Int?
    public var uploadSpeed: Int?

    private enum CodingKeys: String, CodingKey {
        case activeTorrentCount
        case pausedTorrentCount
        case torrentCount
        case downloadSpeed
        case uploadSpeed
    }
}
