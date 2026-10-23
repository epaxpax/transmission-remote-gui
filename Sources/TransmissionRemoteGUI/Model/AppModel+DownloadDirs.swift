import Foundation
import TransmissionKit

/// Per-server favorite and recently used download directories for the Add dialog.
/// The logic (dedupe, limit, normalization) lives in `TransmissionKit.DownloadDirectories`.
extension AppModel {
    /// Favorites and history of the selected server (empty when none is selected).
    var downloadDirs: DownloadDirectories {
        guard let id = selectedServerID else { return DownloadDirectories() }
        return downloadDirsByServer[id] ?? DownloadDirectories()
    }

    /// The daemon's default `download-dir`, if the session info has been loaded.
    var defaultDownloadDir: String? {
        guard let dir = sessionInfo?.downloadDir, !dir.isEmpty else { return nil }
        return dir
    }

    func recordUsedDownloadDir(_ path: String, serverID: UUID) {
        updateDownloadDirs(serverID) { $0.recordUsed(path) }
    }

    func addFavoriteDownloadDir(_ path: String) {
        guard let id = selectedServerID else { return }
        updateDownloadDirs(id) { $0.addFavorite(path) }
    }

    func removeFavoriteDownloadDir(_ path: String) {
        guard let id = selectedServerID else { return }
        updateDownloadDirs(id) { $0.removeFavorite(path) }
    }

    func clearRecentDownloadDirs() {
        guard let id = selectedServerID else { return }
        updateDownloadDirs(id) { $0.clearRecent() }
    }

    func forgetDownloadDirs(for serverID: UUID) {
        guard downloadDirsByServer.removeValue(forKey: serverID) != nil else { return }
        DownloadDirStore.save(downloadDirsByServer)
    }

    private func updateDownloadDirs(_ serverID: UUID, _ change: (inout DownloadDirectories) -> Void) {
        var dirs = downloadDirsByServer[serverID] ?? DownloadDirectories()
        let before = dirs
        change(&dirs)
        guard dirs != before else { return }
        downloadDirsByServer[serverID] = dirs.isEmpty ? nil : dirs
        DownloadDirStore.save(downloadDirsByServer)
    }
}
