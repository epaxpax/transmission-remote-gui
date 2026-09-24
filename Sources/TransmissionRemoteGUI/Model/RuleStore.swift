import Foundation
import Observation
import TransmissionKit

/// Outcome of the last rule pass, shown in the Rules window. The background pass must
/// never raise an alert — a night of them would be unusable — so failures land here.
struct RunSummary: Codable, Hashable {
    var date: Date
    var applied: Int
    var failed: Int
    var messages: [String]
}

/// Persists the rules, which torrents have already been classified, and the last run's
/// outcome. Mirrors `RSSStore`: UserDefaults + JSON, observable on the main actor.
@MainActor
@Observable
final class RuleStore {
    var rules: [TorrentRule] = [] { didSet { persist(rules, rulesKey) } }
    /// Master switch for the whole engine.
    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: enabledKey) } }
    var lastRun: RunSummary? { didSet { persist(lastRun, lastRunKey) } }

    /// Hashes of torrents already handled. Hash rather than id, because ids are only
    /// stable within a session and this set outlives it.
    private var classified: Set<String> = [] { didSet { persist(Array(classified), classifiedKey) } }
    /// Unlike RSSStore's `seen` (a stream of feed items), this set holds one entry per
    /// torrent the user owns — and this app's core audience is seedbox users who
    /// routinely run several thousand torrents at once. At a lower limit the set would
    /// thrash for exactly that audience: every pass would evict entries and force
    /// re-classification, silently overwriting the manual edits "apply once" promises
    /// to preserve. 10,000 hashes is roughly 400 KB in UserDefaults — comfortably fine.
    private static let classifiedLimit = 10000

    private let rulesKey = "torrentRules"
    private let enabledKey = "torrentRulesEnabled"
    private let classifiedKey = "torrentRulesClassified"
    private let lastRunKey = "torrentRulesLastRun"

    init() {
        enabled = UserDefaults.standard.bool(forKey: enabledKey)
        rules = Self.read([TorrentRule].self, rulesKey) ?? []
        classified = Set(Self.read([String].self, classifiedKey) ?? [])
        // Read as an optional, not `RunSummary.self`: persisting a nil `lastRun` writes
        // the JSON literal `null`, and decoding `null` into a non-optional type fails —
        // which `read`'s `try?` would silently turn into `nil` too, but only by
        // accident (through a swallowed decode failure, not a decoded absence). Reading
        // `RunSummary?.self` decodes `null` into a real `nil` on purpose. Do not
        // "simplify" this back to `RunSummary.self`.
        lastRun = Self.read(RunSummary?.self, lastRunKey) ?? nil
    }

    var classifiedHashes: Set<String> { classified }

    func markClassified(_ hash: String) {
        markClassified([hash])
    }

    /// Bulk variant: `classified`'s `didSet` re-encodes and persists the whole set, so
    /// marking a whole pass's worth of torrents one hash at a time would JSON-encode an
    /// ever-growing set once per torrent — seconds of main-actor work for a seedbox-sized
    /// library on the very first pass. Callers marking more than one hash at a time
    /// (`RuleRunner`'s background pass and `applyPlan`) must go through this, not a loop
    /// over the single-hash overload.
    func markClassified(_ hashes: Set<String>) {
        guard !hashes.isEmpty else { return }   // skip the mutation entirely — no pointless persist
        classified.formUnion(hashes)            // one didSet → one persist
        if classified.count > Self.classifiedLimit {
            // Set has no defined order, so this trims an arbitrary excess (bounds
            // memory only) — the same approach RSSStore.markSeen uses.
            classified = Set(classified.prefix(Self.classifiedLimit))
        }
    }

    /// Forgets every classification, so the next pass re-evaluates everything.
    func forgetClassifications() { classified = [] }

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
