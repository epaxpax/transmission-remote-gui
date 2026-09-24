import Foundation

/// What a rule looks at. Exactly one condition per rule: the rule list's order
/// resolves overlaps, which is simpler to reason about than boolean combinations.
///
/// The three conditions match differently on purpose, because the data differs in
/// shape: a tracker host is a substring (so `x.org` also matches `tracker.x.org`),
/// a label is an exact value (labels are a closed set, where substring matching
/// would produce accidental hits), and a name is a pattern.
public enum RuleCondition: Codable, Hashable, Sendable {
    case trackerHost(String)
    case label(String)
    case namePattern(String)
}

/// What a rule does on a match. Every action is non-destructive: the engine never
/// removes a torrent and never deletes data.
public struct RuleActions: Codable, Hashable, Sendable {
    /// Seeding ratio. Applied together with `seedRatioMode = 1`, without which the
    /// daemon would keep using the session default and the rule would do nothing.
    public var seedRatio: Double?
    /// Minutes of seeding inactivity before the daemon stops the torrent.
    public var seedIdleMinutes: Int?
    public var uploadLimitKBps: Int?
    public var downloadLimitKBps: Int?
    /// Labels ADDED to the torrent's existing ones — never a replacement.
    public var addLabels: [String]
    /// Stop the torrent immediately. The only action the daemon cannot carry out
    /// on our behalf, so it only happens while the app is running.
    public var stop: Bool

    public init(seedRatio: Double? = nil, seedIdleMinutes: Int? = nil,
                uploadLimitKBps: Int? = nil, downloadLimitKBps: Int? = nil,
                addLabels: [String] = [], stop: Bool = false) {
        self.seedRatio = seedRatio
        self.seedIdleMinutes = seedIdleMinutes
        self.uploadLimitKBps = uploadLimitKBps
        self.downloadLimitKBps = downloadLimitKBps
        self.addLabels = addLabels
        self.stop = stop
    }

    public var isEmpty: Bool {
        seedRatio == nil && seedIdleMinutes == nil && uploadLimitKBps == nil
            && downloadLimitKBps == nil && addLabels.isEmpty && !stop
    }
}

public struct TorrentRule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var condition: RuleCondition
    public var actions: RuleActions

    public init(id: UUID = UUID(), name: String, enabled: Bool = true,
                condition: RuleCondition, actions: RuleActions) {
        self.id = id; self.name = name; self.enabled = enabled
        self.condition = condition; self.actions = actions
    }
}

/// Condition evaluation. Pure — no network, no UI.
public enum RuleMatcher {
    public static func matches(_ condition: RuleCondition,
                               torrent: Torrent,
                               trackerHosts: [String]) -> Bool {
        switch condition {
        case .trackerHost(let needle):
            let n = needle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { return false }
            return trackerHosts.contains { $0.range(of: n, options: .caseInsensitive) != nil }
        case .label(let wanted):
            let w = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty else { return false }
            return (torrent.labels ?? []).contains { $0.compare(w, options: .caseInsensitive) == .orderedSame }
        case .namePattern(let pattern):
            guard let name = torrent.name else { return false }
            return textMatches(name, pattern: pattern)
        }
    }

    /// Case-insensitive substring, or a regex when the pattern is wrapped in `/…/`.
    /// Mirrors the RSS auto-downloader's rule syntax so users learn one convention.
    /// An invalid regex simply never matches rather than throwing.
    public static func textMatches(_ text: String, pattern: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return false }
        if p.count > 2, p.hasPrefix("/"), p.hasSuffix("/") {
            let body = String(p.dropFirst().dropLast())
            guard let re = try? NSRegularExpression(pattern: body, options: .caseInsensitive) else { return false }
            return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        return text.range(of: p, options: .caseInsensitive) != nil
    }
}
