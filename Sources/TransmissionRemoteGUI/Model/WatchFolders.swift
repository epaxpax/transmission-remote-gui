import Foundation
import TransmissionKit

/// Owned by the app model, so watching continues with the main window closed.
@MainActor
final class WatchFolders {
    private var configured: [ServerConfig] = []
    private var worker: Task<Void, Never>?

    static func folderURL(for path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    }

    static func sameFolder(_ first: URL, _ second: URL) -> Bool {
        if first == second { return true }
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
        guard let a = try? first.resourceValues(forKeys: keys),
              let b = try? second.resourceValues(forKeys: keys),
              let file = a.fileResourceIdentifier, let volume = a.volumeIdentifier else { return false }
        return file.isEqual(b.fileResourceIdentifier) && volume.isEqual(b.volumeIdentifier)
    }

    func update(servers: [ServerConfig]) {
        var folders: [URL] = []
        let next = servers.filter { server in
            guard let path = server.watchFolderPath, path.hasPrefix("/") else { return false }
            let folder = Self.folderURL(for: path)
            guard !folders.contains(where: { Self.sameFolder($0, folder) }) else { return false }
            folders.append(folder)
            return true
        }
        guard configured != next else { return }
        configured = next

        let previous = worker
        previous?.cancel()
        let targets = Array(zip(next, folders))
        worker = Task.detached(priority: .utility) {
            // Finish old work before a folder can be assigned to another server.
            await previous?.value
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                for (server, folder) in targets {
                    group.addTask {
                        let client = RPCClient(config: server, session: server.makeSession())
                        var importer = WatchFolderImporter(folder: folder)
                        while !Task.isCancelled {
                            await importer.scan { metainfo in
                                let result = try await client.torrentAdd(metainfoBase64: metainfo, paused: nil)
                                return result.added != nil || result.isDuplicate
                            }
                            try? await Task.sleep(for: WatchFolderImporter.scanInterval)
                        }
                    }
                }
            }
        }
    }
}
