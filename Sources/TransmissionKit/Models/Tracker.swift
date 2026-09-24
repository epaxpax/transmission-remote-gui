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

/// Lightweight tracker entry (`trackers` array) — far smaller than `trackerStats`,
/// which is why the rule engine asks for this one.
public struct Tracker: Codable, Hashable, Sendable {
    public var id: Int?
    public var announce: String?
    public var scrape: String?
    /// Short site name. Transmission 4.0+ only — absent on 3.x.
    public var sitename: String?
    public var tier: Int?

    public init(id: Int? = nil, announce: String? = nil, scrape: String? = nil,
                sitename: String? = nil, tier: Int? = nil) {
        self.id = id; self.announce = announce; self.scrape = scrape
        self.sitename = sitename; self.tier = tier
    }

    /// Host the rule conditions match against: `sitename` when the daemon supplies it
    /// (4.0+), otherwise the host parsed out of the announce URL (3.x).
    public var matchHost: String? {
        if let sitename, !sitename.isEmpty { return sitename }
        guard let announce, let host = URLComponents(string: announce)?.host, !host.isEmpty else { return nil }
        return host
    }
}
