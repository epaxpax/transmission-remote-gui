import Foundation

/// Tracker state (`trackerStats` array).
public struct TrackerStat: Codable, Hashable, Sendable, Identifiable {
    public var id: String { announce ?? host ?? UUID().uuidString }
    public var host: String?
    public var announce: String?
    public var tier: Int?
    public var lastAnnounceResult: String?
    public var lastAnnounceSucceeded: Bool?
    public var seederCount: Int?
    public var leecherCount: Int?
    public var nextAnnounceTime: Int?

    public var displayHost: String {
        host ?? announce ?? "—"
    }
}
