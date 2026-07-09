import Foundation
import Observation

/// A watched RSS/Atom feed.
struct RSSFeed: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var url: String
    var enabled: Bool = true
}

/// A download rule: items whose title matches `pattern` get added automatically.
/// `pattern` is a case-insensitive substring, or a regex when wrapped in `/…/`.
struct RSSRule: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var pattern: String
    var enabled: Bool = true
}

/// Persists RSS feeds + rules (UserDefaults, JSON) and the set of already-downloaded
/// item GUIDs (dedup). Also does title→rule matching.
@MainActor
@Observable
final class RSSStore {
    var feeds: [RSSFeed] = [] { didSet { persist(feeds, feedsKey) } }
    var rules: [RSSRule] = [] { didSet { persist(rules, rulesKey) } }
    /// Master switch for the whole auto-downloader.
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: enabledKey) }
    }

    private var seen: Set<String> = []
    private static let seenLimit = 2000

    private let feedsKey = "rssFeeds"
    private let rulesKey = "rssRules"
    private let seenKey = "rssSeenGuids"
    private let enabledKey = "rssEnabled"

    init() {
        enabled = UserDefaults.standard.bool(forKey: enabledKey)
        feeds = Self.read([RSSFeed].self, feedsKey) ?? []
        rules = Self.read([RSSRule].self, rulesKey) ?? []
        seen = Set(Self.read([String].self, seenKey) ?? [])
    }

    // MARK: Dedup

    func isSeen(_ guid: String) -> Bool { seen.contains(guid) }

    func markSeen(_ guid: String) {
        seen.insert(guid)
        if seen.count > Self.seenLimit {
            // Drop oldest-ish by trimming arbitrary excess (Set has no order; bound memory only).
            seen = Set(seen.prefix(Self.seenLimit))
        }
        persist(Array(seen), seenKey)
    }

    // MARK: Matching

    /// True if the title matches ANY enabled rule.
    func titleMatchesAnyRule(_ title: String) -> Bool {
        rules.contains { $0.enabled && Self.matches(title, $0.pattern) }
    }

    /// Case-insensitive substring match, or regex when the pattern is wrapped in `/…/`.
    static func matches(_ title: String, _ pattern: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return false }
        if p.count > 2, p.hasPrefix("/"), p.hasSuffix("/") {
            let body = String(p.dropFirst().dropLast())
            guard let re = try? NSRegularExpression(pattern: body, options: .caseInsensitive) else { return false }
            return re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
        }
        return title.range(of: p, options: .caseInsensitive) != nil
    }

    // MARK: Persistence helpers

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
