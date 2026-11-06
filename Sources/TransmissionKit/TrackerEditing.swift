import Foundation

/// Transmission 4.0 introduced the tier-preserving trackerList setter.
public enum TrackerListSupport {
    public static let minimumRPCVersion = 17

    public static func isSupported(rpcVersion: Int?) -> Bool {
        (rpcVersion ?? 0) >= minimumRPCVersion
    }
}

public enum TrackerEdit: Sendable {
    case add(String)
    /// Identify the tracker by its full announce URL, then resolve its current daemon ID.
    case remove(String)

    public static func validatedURL(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URLComponents(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https", "udp"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return text
    }

    /// Sort tiers numerically while retaining the daemon's URL order inside each tier.
    public static func trackerList(_ trackers: [Tracker]) throws -> String {
        var tiers: [Int: [String]] = [:]
        for tracker in trackers {
            guard let announce = tracker.announce, !announce.isEmpty,
                  !announce.contains(where: { $0.isNewline }), let tier = tracker.tier else {
                throw TrackerEditError.incompleteTrackers
            }
            tiers[tier, default: []].append(announce)
        }
        return tiers.keys.sorted().map { tiers[$0]!.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}

public enum TrackerEditError: Error, Sendable {
    case invalidURL
    case torrentMissing
    case incompleteTrackers
}

public extension RPCClient {
    /// Read immediately before writing: edits must preserve trackers changed by another client.
    func editTracker(_ edit: TrackerEdit, torrentID: Int, rpcVersion: Int?) async throws {
        if case .add(let url) = edit, TrackerEdit.validatedURL(url) == nil {
            throw TrackerEditError.invalidURL
        }
        let ids = RPCIds.ids([.id(torrentID)])
        guard let torrent = try await torrentGet(fields: ["id", "trackers"], ids: ids).first,
              torrent.id == torrentID else { throw TrackerEditError.torrentMissing }
        guard let trackers = torrent.trackers else { throw TrackerEditError.incompleteTrackers }
        var args = TorrentSetArgs(ids: ids)
        switch edit {
        case .add(let text):
            guard let url = TrackerEdit.validatedURL(text) else { throw TrackerEditError.invalidURL }
            guard !trackers.contains(where: { $0.announce == url }) else { return }
            if TrackerListSupport.isSupported(rpcVersion: rpcVersion) {
                let current = try TrackerEdit.trackerList(trackers)
                args.trackerList = current.isEmpty ? url : current + "\n\n" + url
            } else {
                args.trackerAdd = [url]
            }
        case .remove(let url):
            guard let target = trackers.first(where: { $0.announce == url }) else { return }
            if TrackerListSupport.isSupported(rpcVersion: rpcVersion) {
                args.trackerList = try TrackerEdit.trackerList(trackers.filter { $0.announce != url })
            } else {
                guard let id = target.id else { throw TrackerEditError.incompleteTrackers }
                args.trackerRemove = [id]
            }
        }
        try Task.checkCancellation()
        try await torrentSet(args)
    }
}
