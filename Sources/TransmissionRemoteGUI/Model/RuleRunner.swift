import Foundation
import TransmissionKit

/// Fetches exactly what the rules need, asks `RuleEngine` what should happen, and
/// carries it out. All the decisions live in the Kit; this type only does I/O.
enum RuleRunner {

    /// Builds a plan for the given torrent ids.
    ///
    /// The narrow `ruleInputs` query is deliberate: the 5-second list poll must not
    /// start carrying every torrent's announce URLs just so the rules can read them.
    static func plan(client: RPCClient,
                     rules: [TorrentRule],
                     ids: [Int],
                     alreadyClassified: Set<String>,
                     force: Bool) async throws -> [PlannedChange] {
        guard !rules.isEmpty, !ids.isEmpty else { return [] }
        let torrents = try await client.torrentGet(fields: TorrentFields.ruleInputs,
                                                   ids: .ids(ids.map { .id($0) }))
        var hosts: [Int: [String]] = [:]
        for torrent in torrents {
            // flatMap, not compactMap: each tracker contributes both its sitename and its
            // announce host (see `Tracker.matchHosts`), so a rule typed from either form
            // matches on both 3.x and 4.x daemons.
            hosts[torrent.id] = (torrent.trackers ?? []).flatMap(\.matchHosts)
        }
        return RuleEngine.plan(rules: rules,
                               torrents: torrents,
                               trackerHosts: hosts,
                               alreadyClassified: alreadyClassified,
                               force: force)
    }

    /// Applies a plan, one torrent at a time — never batched across torrents — so a
    /// single failure cannot take the rest of the batch with it. (A change that both
    /// sets fields and stops still sends two requests, `torrent-set` then
    /// `torrent-stop`, for that one torrent.) Returns the hashes that were applied
    /// successfully and the messages of those that were not.
    static func apply(_ plan: [PlannedChange], client: RPCClient) async -> (applied: [String], failures: [String]) {
        var applied: [String] = []
        var failures: [String] = []
        for change in plan {
            do {
                // A stop-only change has nothing to put in a torrent-set body; sending
                // one anyway would be a pointless round trip.
                if change.needsTorrentSet {
                    try await client.torrentSet(RuleEngine.arguments(for: change))
                }
                if change.alsoStop {
                    try await client.torrentStop(ids: .ids([.id(change.torrentID)]))
                }
                if let hash = change.torrentHash { applied.append(hash) }
            } catch {
                let reason = await locError(error)
                failures.append("\(change.torrentName): \(reason)")
            }
        }
        return (applied, failures)
    }
}
