import Foundation

/// Which torrent property a planned change touches. A stable key, not display text —
/// the UI localizes it.
public enum RuleField: String, Hashable, Sendable, CaseIterable {
    case seedRatio, seedIdle, uploadLimit, downloadLimit, labels, stop
}

/// One field's before/after, for the dry-run view.
public struct FieldChange: Hashable, Sendable {
    public let field: RuleField
    public let before: String
    public let after: String

    public init(field: RuleField, before: String, after: String) {
        self.field = field; self.before = before; self.after = after
    }
}

/// What would happen to one torrent. Value-typed on purpose: it carries the meaning
/// of the change, while turning it into RPC arguments is a separate step.
public struct PlannedChange: Hashable, Sendable, Identifiable {
    public var id: Int { torrentID }
    public let torrentID: Int
    public let torrentHash: String?
    public let torrentName: String
    public let ruleID: UUID
    public let ruleName: String
    public let changes: [FieldChange]
    /// Only the fields that actually differ — never the rule's full action set.
    public let effect: RuleActions
    public let alsoStop: Bool
}

public enum RuleEngine {

    /// Works out what the rules would do. Pure: no network, no side effects.
    ///
    /// - Parameters:
    ///   - trackerHosts: torrent id → its trackers' match hosts. Keyed by id because a
    ///     single call works on one snapshot, where ids are stable.
    ///   - alreadyClassified: hashes of torrents a previous run already handled. Hash,
    ///     not id, because this set outlives the session.
    ///   - force: ignore `alreadyClassified` (manual "run now", and the editor preview).
    public static func plan(rules: [TorrentRule],
                            torrents: [Torrent],
                            trackerHosts: [Int: [String]],
                            alreadyClassified: Set<String>,
                            force: Bool = false) -> [PlannedChange] {
        let active = rules.filter(\.enabled)
        guard !active.isEmpty else { return [] }

        return torrents.compactMap { torrent -> PlannedChange? in
            if !force, let hash = torrent.hashString, alreadyClassified.contains(hash) { return nil }
            let hosts = trackerHosts[torrent.id] ?? []
            guard let rule = active.first(where: {
                RuleMatcher.matches($0.condition, torrent: torrent, trackerHosts: hosts)
            }) else { return nil }

            var effect = RuleActions()
            var changes: [FieldChange] = []

            // The limit only takes effect together with mode 1, so a torrent that holds
            // the right number in GLOBAL mode still needs the write.
            if let wanted = rule.actions.seedRatio,
               torrent.seedRatioLimit != wanted || torrent.seedRatioMode != 1 {
                effect.seedRatio = wanted
                changes.append(FieldChange(field: .seedRatio,
                                           before: describe(torrent.seedRatioLimit, mode: torrent.seedRatioMode),
                                           after: String(wanted)))
            }
            if let wanted = rule.actions.seedIdleMinutes,
               torrent.seedIdleLimit != wanted || torrent.seedIdleMode != 1 {
                effect.seedIdleMinutes = wanted
                // Separate formatter, because the idle limit is an Int: routing it
                // through the Double formatter would print "30.0 → 30" in the dry-run.
                changes.append(FieldChange(field: .seedIdle,
                                           before: describeInt(torrent.seedIdleLimit, mode: torrent.seedIdleMode),
                                           after: String(wanted)))
            }
            if let wanted = rule.actions.uploadLimitKBps,
               torrent.uploadLimit != wanted || torrent.uploadLimited != true {
                effect.uploadLimitKBps = wanted
                changes.append(FieldChange(field: .uploadLimit,
                                           before: torrent.uploadLimited == true ? String(torrent.uploadLimit ?? 0) : "—",
                                           after: String(wanted)))
            }
            if let wanted = rule.actions.downloadLimitKBps,
               torrent.downloadLimit != wanted || torrent.downloadLimited != true {
                effect.downloadLimitKBps = wanted
                changes.append(FieldChange(field: .downloadLimit,
                                           before: torrent.downloadLimited == true ? String(torrent.downloadLimit ?? 0) : "—",
                                           after: String(wanted)))
            }
            if !rule.actions.addLabels.isEmpty {
                let existing = torrent.labels ?? []
                let merged = mergedLabels(existing: existing, adding: rule.actions.addLabels)
                if merged != existing {
                    effect.addLabels = merged
                    changes.append(FieldChange(field: .labels,
                                               before: existing.joined(separator: ", "),
                                               after: merged.joined(separator: ", ")))
                }
            }
            let mustStop = rule.actions.stop && !torrent.isPaused
            if mustStop {
                effect.stop = true
                changes.append(FieldChange(field: .stop, before: torrent.statusText, after: "Leállítva"))
            }

            guard !changes.isEmpty else { return nil }
            return PlannedChange(torrentID: torrent.id,
                                 torrentHash: torrent.hashString,
                                 torrentName: torrent.displayName,
                                 ruleID: rule.id,
                                 ruleName: rule.name,
                                 changes: changes,
                                 effect: effect,
                                 alsoStop: mustStop)
    	}
    }

    /// Turns a planned change into `torrent-set` arguments. Separate from `plan` so the
    /// plan stays a plain value and the wire format can change independently.
    public static func arguments(for change: PlannedChange) -> TorrentSetArgs {
        var args = TorrentSetArgs(ids: .ids([.id(change.torrentID)]))
        if let ratio = change.effect.seedRatio {
            args.seedRatioLimit = ratio
            args.seedRatioMode = 1     // TR_RATIOLIMIT_SINGLE — without this the daemon ignores the limit
        }
        if let idle = change.effect.seedIdleMinutes {
            args.seedIdleLimit = idle
            args.seedIdleMode = 1      // TR_IDLELIMIT_SINGLE
        }
        if let up = change.effect.uploadLimitKBps {
            args.uploadLimit = up
            args.uploadLimited = true
        }
        if let down = change.effect.downloadLimitKBps {
            args.downloadLimit = down
            args.downloadLimited = true
        }
        if !change.effect.addLabels.isEmpty {
            args.labels = change.effect.addLabels
        }
        return args
    }

    /// Existing labels first, then the new ones, without duplicates (case-insensitive).
    static func mergedLabels(existing: [String], adding: [String]) -> [String] {
        var result = existing
        for label in adding {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !result.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
                result.append(trimmed)
            }
        }
        return result
    }

    /// A limit in GLOBAL/UNLIMITED mode is not in force, so it is shown as "—".
    private static func describe(_ value: Double?, mode: Int?) -> String {
        guard mode == 1, let value else { return "—" }
        return String(value)
    }

    private static func describeInt(_ value: Int?, mode: Int?) -> String {
        guard mode == 1, let value else { return "—" }
        return String(value)
    }
}
