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

    /// Every string a tracker rule may match against: the `sitename` when the daemon
    /// supplies it (4.0+) *and* the host parsed out of the announce URL.
    ///
    /// Both, never one or the other. `sitename` is short ("example"), while the host is
    /// the full name ("tracker.example.org") — and the full host is what the app shows
    /// the user, in the torrent detail view's tracker column. Offering only `sitename`
    /// on a 4.x daemon meant a rule typed from what the UI displayed matched nothing,
    /// and the dry run reported "nothing would change" — indistinguishable from a rule
    /// that legitimately matches nothing. Since `RuleMatcher` substring-matches over
    /// this array, an extra candidate can only ever make a rule more permissive.
    /// The host parsed out of the announce URL ("tracker.example.org"), as the UI shows it.
    public var announceHost: String? {
        guard let announce, let host = URLComponents(string: announce)?.host, !host.isEmpty else { return nil }
        return host
    }

    public var matchHosts: [String] {
        var out: [String] = []
        if let sitename, !sitename.isEmpty { out.append(sitename) }
        if let host = announceHost { out.append(host) }
        return out
    }
}
