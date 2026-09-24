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
    private static let classifiedLimit = 2000

    private let rulesKey = "torrentRules"
    private let enabledKey = "torrentRulesEnabled"
    private let classifiedKey = "torrentRulesClassified"
    private let lastRunKey = "torrentRulesLastRun"

    init() {
        enabled = UserDefaults.standard.bool(forKey: enabledKey)
        rules = Self.read([TorrentRule].self, rulesKey) ?? []
        classified = Set(Self.read([String].self, classifiedKey) ?? [])
        lastRun = Self.read(RunSummary.self, lastRunKey)
    }

    var classifiedHashes: Set<String> { classified }

    func markClassified(_ hash: String) {
        classified.insert(hash)
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
