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

/// Pure, UI-independent rules and layout for the torrent list's context menu.
public enum TorrentRowMenu {

    /// One entry of the menu, in display order. `titleKey` is the Hungarian source string
    /// the app looks up with `loc()`; `separatorAfter` draws a divider below the item.
    ///
    /// The layout lives here rather than in the view so a test can assert that every
    /// command actually reaches the menu — a command missing from the layout would
    /// otherwise compile happily and simply never appear.
    public struct Entry: Sendable {
        public let command: TorrentRowCommand
        public let titleKey: String
        public let separatorAfter: Bool
    }

    public static let layout: [Entry] = [
        Entry(command: .start, titleKey: "Indítás", separatorAfter: false),
        Entry(command: .stop, titleKey: "Leállítás", separatorAfter: true),
        Entry(command: .move, titleKey: "Áthelyezés…", separatorAfter: false),
        Entry(command: .rename, titleKey: "Átnevezés…", separatorAfter: true),
        Entry(command: .verify, titleKey: "Ellenőrzés (verify)", separatorAfter: false),
        Entry(command: .reannounce, titleKey: "Újrabejelentés a trackernek", separatorAfter: true),
        Entry(command: .copyName, titleKey: "Név másolása", separatorAfter: false),
        Entry(command: .copyHash, titleKey: "Hash másolása", separatorAfter: true),
        Entry(command: .removeKeepData, titleKey: "Törlés a listából", separatorAfter: false),
        Entry(command: .removeWithData, titleKey: "Törlés az adatokkal együtt", separatorAfter: false),
    ]

    /// The rows a right-click should act on.
    ///
    /// Standard macOS behaviour: clicking inside the selection acts on the whole selection,
    /// clicking outside it retargets to that single row, and clicking empty space (`row < 0`)
    /// targets nothing — the caller then shows no menu at all.
    public static func targetRows(clicked row: Int, selection: IndexSet) -> IndexSet {
        guard row >= 0 else { return IndexSet() }
        return selection.contains(row) ? selection : IndexSet(integer: row)
    }

    /// Maps row indices to torrents, dropping indices the table no longer has data for.
    ///
    /// The list is refreshed by polling, so a row index captured a moment ago can point
    /// past the end of the current snapshot.
    public static func targets(rows: IndexSet, in torrents: [Torrent]) -> [Torrent] {
        rows.compactMap { $0 >= 0 && $0 < torrents.count ? torrents[$0] : nil }
    }

    /// Whether `command` applies to the given target torrents.
    public static func isEnabled(_ command: TorrentRowCommand, for torrents: [Torrent]) -> Bool {
        guard !torrents.isEmpty else { return false }
        switch command {
        case .start:
            return torrents.contains { $0.isPaused }
        case .stop:
            return torrents.contains { !$0.isPaused }
        case .verify:
            // Re-checking something already being (or queued to be) checked does nothing.
            return torrents.contains { !isChecking($0) }
        case .reannounce:
            // A stopped torrent has no active announce to refresh.
            return torrents.contains { !$0.isPaused }
        case .rename:
            // `torrent-rename-path` takes exactly one torrent, and the old path is its name.
            return torrents.count == 1 && hasName(torrents[0])
        case .copyName:
            return torrents.contains(where: hasName)
        case .copyHash:
            return torrents.contains { $0.hashString?.isEmpty == false }
        case .move, .removeKeepData, .removeWithData:
            return true
        }
    }

    /// Trims a new torrent name and rejects anything that is not a single, plain path
    /// component: `torrent-rename-path` renames one component, not a path, and `.`/`..`
    /// are traversal shapes the daemon must never be asked to resolve.
    ///
    /// `current` (the existing name) is rejected as well — renaming to the same value is
    /// a wasted round trip that the daemon answers with an error.
    public static func sanitizedName(_ raw: String, current: String? = nil) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              trimmed != ".", trimmed != "..",
              trimmed != current else { return nil }
        return trimmed
    }

    /// Trims a target directory and rejects anything the daemon would resolve surprisingly:
    /// an empty path, a relative one (resolved against the daemon's working directory) and
    /// a `~` path (the daemon does not expand it).
    ///
    /// Windows drive paths (`C:\…`) are accepted — the client is macOS-only, the daemon is not.
    public static func sanitizedLocation(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isAbsolutePath(trimmed) else { return nil }
        return trimmed
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\\\") { return true }
        // Drive-letter path such as C:\Downloads or C:/Downloads.
        let chars = Array(path)
        guard chars.count >= 3, chars[1] == ":", chars[0].isLetter else { return false }
        return chars[2] == "\\" || chars[2] == "/"
    }

    private static func isChecking(_ torrent: Torrent) -> Bool {
        torrent.statusValue == .verifying || torrent.statusValue == .queuedToVerify
    }

    private static func hasName(_ torrent: Torrent) -> Bool {
        torrent.name?.isEmpty == false
    }
}
