import Foundation

/// The actions the torrent list's context menu can offer.
///
/// The cases live in `TransmissionKit` (not in the AppKit view) so the rules that decide
/// *when* an action applies can be unit-tested without a running UI.
public enum TorrentRowCommand: String, CaseIterable, Sendable {
    case start
    case stop
    case move
    case rename
    case verify
    case reannounce
    case copyName
    case copyHash
    case removeKeepData
    case removeWithData
}

/// Pure, UI-independent rules for the torrent list's context menu.
public enum TorrentRowMenu {

    /// The rows a right-click should act on.
    ///
    /// Standard macOS behaviour: clicking inside the selection acts on the whole selection,
    /// clicking outside it retargets to that single row, and clicking empty space (`row < 0`)
    /// targets nothing — the caller then shows no menu at all.
    public static func targetRows(clicked row: Int, selection: IndexSet) -> IndexSet {
        guard row >= 0 else { return IndexSet() }
        return selection.contains(row) ? selection : IndexSet(integer: row)
    }

    /// Whether `command` applies to the given target torrents.
    public static func isEnabled(_ command: TorrentRowCommand, for torrents: [Torrent]) -> Bool {
        guard !torrents.isEmpty else { return false }
        switch command {
        case .start:
            return torrents.contains { $0.isPaused }
        case .stop:
            return torrents.contains { !$0.isPaused }
        case .rename:
            // `torrent-rename-path` takes exactly one torrent, and the old path is its name.
            return torrents.count == 1 && hasName(torrents[0])
        case .copyName:
            return torrents.contains(where: hasName)
        case .copyHash:
            return torrents.contains { $0.hashString?.isEmpty == false }
        case .move, .verify, .reannounce, .removeKeepData, .removeWithData:
            return true
        }
    }

    /// Trims a new torrent name and rejects it when empty or when it contains a path
    /// separator (`torrent-rename-path` renames one path component, not a path).
    public static func sanitizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
        return trimmed
    }

    /// Trims a target directory and rejects an empty one.
    public static func sanitizedLocation(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func hasName(_ torrent: Torrent) -> Bool {
        torrent.name?.isEmpty == false
    }
}
