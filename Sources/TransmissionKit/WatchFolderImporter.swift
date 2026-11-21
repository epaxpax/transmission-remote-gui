import Darwin
import Foundation

/// Imports stable files from the top level of one folder. One task owns each importer.
public struct WatchFolderImporter {
    public static let scanInterval: Duration = .seconds(2)
    private static let retryInterval: Duration = .seconds(30)
    public static let maximumFileSize = 10_000_000

    public enum Problem: Equatable, Sendable {
        case cannotReadFolder
        case cannotReadFile(String)
        case cannotRenameFile(String)
        case fileTooLarge(String)
    }

    private enum Marker: String {
        case added, invalid
    }

    private struct FileStamp: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: UInt64
        let modified: Date

        init?(_ url: URL) throws {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular,
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
        var marker: Marker?
        var problem: Problem?
    }

    private let folder: URL
    private var observations: [URL: Observation] = [:]

    public init(folder: URL) {
        self.folder = folder
    }

    /// The submit closure returns true only when the daemon confirms the torrent is present.
    /// Keeping unsuccessful files intact allows retry after a connection or filesystem failure.
    @discardableResult
    public mutating func scan(
        now: ContinuousClock.Instant = .now,
        submit: (String) async throws -> Bool
    ) async -> Problem? {
        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles])
        } catch {
            return .cannotReadFolder
        }
        let candidates = urls.filter { $0.pathExtension.lowercased() == "torrent" }
        let present = Set(candidates)
        observations = observations.filter { present.contains($0.key) }
        var problem: Problem?

        for url in candidates {
            guard !Task.isCancelled else { return nil }
            let name = url.lastPathComponent
            let stamp: FileStamp
            do {
                guard let current = try FileStamp(url) else {
                    observations[url] = nil
                    continue
                }
                stamp = current
            } catch {
                problem = problem ?? .cannotReadFile(name)
                continue
            }
            guard stamp.size <= UInt64(Self.maximumFileSize) else {
                observations[url] = nil
                problem = problem ?? .fileTooLarge(name)
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

            do {
                guard let data = try Self.read(url, stamp: stamp) else {
                    observations[url] = nil
                    continue
                }
                observation.problem = nil
                observations[url] = observation

                if observation.marker == nil {
                    try Task.checkCancellation()
                    if data.isEmpty {
                        observation.marker = .invalid
                    } else {
                        do {
                            guard try await submit(data.base64EncodedString()) else { continue }
                            observation.marker = .added
                        } catch RPCError.rpcFailure(let reason)
                            where reason == "invalid or corrupt torrent file" || reason == "unrecognized info" {
                            // Transmission 3 and 4 use different messages for bad metainfo. Unknown RPC and
                            // transport failures keep the source available for another attempt.
                            observation.marker = .invalid
                        } catch is CancellationError {
                            return nil
                        } catch {
                            continue
                        }
                    }
                    observations[url] = observation
                }

                // Never rename a file that was replaced while the RPC was in flight.
                guard try Self.read(url, stamp: stamp) == data else {
                    observations[url] = nil
                    continue
                }
            } catch is CancellationError {
                return nil
            } catch {
                observations[url]?.problem = .cannotReadFile(name)
                continue
            }

            if let marker = observation.marker {
                do {
                    try Self.mark(url, as: marker, using: fm)
                    observations[url] = nil
                } catch {
                    // Retry only the rename after a terminal response, without another RPC.
                    observations[url]?.problem = .cannotRenameFile(name)
                }
            }
        }
        return problem ?? observations.values.compactMap(\.problem).first
    }

    private static func read(_ url: URL, stamp: FileStamp) throws -> Data? {
        // The path can change between the initial stat and open. Refuse symlinks and
        // bound the read even if a writer grows or replaces the file in that window.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard info.st_mode & S_IFMT == S_IFREG,
              UInt64(truncatingIfNeeded: info.st_dev) == stamp.device,
              info.st_ino == stamp.inode, info.st_size == Int64(stamp.size) else { return nil }
        let data = stamp.size == 0 ? Data() : try handle.read(upToCount: Int(stamp.size)) ?? Data()
        guard UInt64(data.count) == stamp.size, try FileStamp(url) == stamp else { return nil }
        return data
    }

    private static func mark(_ source: URL, as marker: Marker, using fm: FileManager) throws {
        let folder = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        var destination = source.appendingPathExtension(marker.rawValue)
        var suffix = 2
        while fm.fileExists(atPath: destination.path) {
            // Preserve previous imports even if a browser reuses the same name.
            destination = folder.appendingPathComponent("\(stem).\(suffix).torrent.\(marker.rawValue)")
            suffix += 1
        }
        try fm.moveItem(at: source, to: destination)
    }
}
