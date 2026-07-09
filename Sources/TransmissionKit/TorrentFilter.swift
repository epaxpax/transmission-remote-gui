import Foundation

/// The sidebar filter categories (like the left panel in transgui).
public enum TorrentFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case downloading
    case completed
    case active
    case inactive
    case stopped
    case error

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "Összes"
        case .downloading: return "Letöltés alatt"
        case .completed: return "Kész"
        case .active: return "Aktív"
        case .inactive: return "Inaktív"
        case .stopped: return "Leállítva"
        case .error: return "Hibás"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        case .active: return "bolt.circle"
        case .inactive: return "pause.circle"
        case .stopped: return "stop.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    /// Whether the torrent matches this filter.
    public func matches(_ torrent: Torrent) -> Bool {
        switch self {
        case .all:
            return true
        case .downloading:
            return torrent.statusValue == .downloading || torrent.statusValue == .queuedToDownload
        case .completed:
            return (torrent.percentDone ?? 0) >= 1.0
        case .active:
            return torrent.isActive
        case .inactive:
            return !torrent.isActive && !torrent.isPaused
        case .stopped:
            return torrent.isPaused
        case .error:
            return torrent.hasError
        }
    }
}
