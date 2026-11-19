import Foundation

/// Imports stable files from the top level of one folder. One task owns each importer.
public struct WatchFolderImporter {
    public static let scanInterval: Duration = .seconds(2)
    private static let retryInterval: Duration = .seconds(30)

    private struct FileStamp: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: UInt64
        let modified: Date

        init?(_ url: URL) {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  let device = attrs[.systemNumber] as? NSNumber,
                  let inode = attrs[.systemFileNumber] as? NSNumber,
                  let size = attrs[.size] as? NSNumber,
                  let modified = attrs[.modificationDate] as? Date else { return nil }
            self.device = device.uint64Value
            self.inode = inode.uint64Value
            self.size = size.uint64Value
            self.modified = modified
        }
    }

    private struct Observation {
        var stamp: FileStamp
        var nextAttempt: ContinuousClock.Instant
        var added = false
    }

    private let folder: URL
    private var observations: [URL: Observation] = [:]

    public init(folder: URL) {
        self.folder = folder
    }

    /// The submit closure returns true only when the daemon confirms the torrent is present.
    /// Keeping unsuccessful files intact allows retry after a connection or filesystem failure.
    public mutating func scan(
        now: ContinuousClock.Instant = .now,
        submit: (String) async throws -> Bool
    ) async {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles]) else {
            observations.removeAll()
            return
        }
        let candidates = urls.filter { $0.pathExtension.lowercased() == "torrent" }
        let present = Set(candidates)
        observations = observations.filter { present.contains($0.key) }

        for url in candidates {
            guard !Task.isCancelled else { return }
            guard let stamp = FileStamp(url) else {
                observations[url] = nil
                continue
            }
            guard var observation = observations[url], observation.stamp == stamp else {
                // Give Finder, browsers and other writers time to finish copying the file.
                observations[url] = Observation(stamp: stamp, nextAttempt: now.advanced(by: Self.scanInterval))
                continue
            }
            guard now >= observation.nextAttempt else { continue }
            observation.nextAttempt = now.advanced(by: Self.retryInterval)
            observations[url] = observation

            guard let data = try? Data(contentsOf: url), !data.isEmpty, FileStamp(url) == stamp else { continue }
            if !observation.added {
                do {
                    try Task.checkCancellation()
                    guard try await submit(data.base64EncodedString()) else { continue }
                    observation.added = true
                    observations[url] = observation
                } catch is CancellationError {
                    return
                } catch {
                    continue
                }
            }

            // A file replaced during the RPC must be processed separately on the next scan.
            guard FileStamp(url) == stamp, (try? Data(contentsOf: url)) == data else {
                observations[url] = nil
                continue
            }
            if Self.markAdded(url, using: fm) {
                observations[url] = nil
            }
        }
    }

    private static func markAdded(_ source: URL, using fm: FileManager) -> Bool {
        let folder = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        var destination = source.appendingPathExtension("added")
        var suffix = 2
        while fm.fileExists(atPath: destination.path) {
            // Preserve previous imports even if a browser reuses the same name.
            destination = folder.appendingPathComponent("\(stem).\(suffix).torrent.added")
            suffix += 1
        }
        do {
            try fm.moveItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }
}
