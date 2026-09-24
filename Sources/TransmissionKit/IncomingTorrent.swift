import Foundation

/// A torrent handed to the app from outside: Finder "Open" / "Open With", a magnet link
/// clicked in a browser, or a drag & drop.
///
/// The classification and the "hold until connected" queue live here (not in the app target)
/// so they are covered by `KitTests`; the app only glues AppKit's open events to them.
public enum IncomingTorrent: Equatable, Sendable {
    /// A local `.torrent` file — its contents are sent as base64 metainfo.
    case file(URL)
    /// A magnet link or an http(s) URL — sent to the daemon as `filename`.
    case link(String)

    /// Classifies a URL, or `nil` if it is not something the daemon can add.
    public static func classify(_ url: URL) -> IncomingTorrent? {
        if url.isFileURL {
            return url.pathExtension.lowercased() == "torrent" ? .file(url) : nil
        }
        switch url.scheme?.lowercased() {
        case "magnet", "http", "https": return .link(url.absoluteString)
        default: return nil
        }
    }

    /// Classifies pasted / dragged text (magnet or http(s) link), or `nil`.
    public static func classify(text: String) -> IncomingTorrent? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("magnet:") || value.hasPrefix("http"), let url = URL(string: value) else { return nil }
        return classify(url)
    }
}

/// Holds incoming torrents while there is no connection (e.g. a cold launch by double-clicking
/// a `.torrent`: the open event arrives before the first successful poll), then hands them
/// over in arrival order exactly once. Duplicates within the queue are dropped.
public struct IncomingQueue: Sendable {
    public private(set) var pending: [IncomingTorrent] = []

    public init() {}

    public mutating func enqueue(_ items: [IncomingTorrent]) {
        for item in items where !pending.contains(item) { pending.append(item) }
    }

    /// Returns everything queued and empties the queue.
    public mutating func drain() -> [IncomingTorrent] {
        defer { pending = [] }
        return pending
    }
}
