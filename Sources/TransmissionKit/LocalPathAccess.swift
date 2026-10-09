import Foundation

/// Read-only local checks. No mounting, directory creation or remote filesystem writes.
public enum LocalPathAccess {
    // A single worker bounds outstanding filesystem probes if an SMB operation stalls.
    private static let queue = DispatchQueue(label: "TransmissionRemoteGUI.pathAccess", qos: .userInitiated)

    public static func validate(_ location: MappedPath, mountedVolumes: [URL]? = nil) throws -> URL {
        let url = location.url
        let components = url.path.split(separator: "/")
        if components.count >= 2, components[0] == "Volumes" {
            let volumePath = "/Volumes/" + components[1]
            let volumes = mountedVolumes ?? FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil, options: []) ?? []
            guard volumes.contains(where: { $0.path == volumePath }) else { throw PathMappingError.unmountedVolume }
        }
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw PathMappingError.notFound
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw PathMappingError.notReadable
        }
        // Resolving an absent path can retain a macOS /tmp or /var alias while an
        // existing root resolves to /private/...; report absence before containment.
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let root = location.localRoot.resolvingSymlinksInPath().standardizedFileURL
        guard PathMapping.contains(resolved.path, in: root.path) else { throw PathMappingError.outsideMapping }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw PathMappingError.notReadable }
        return url
    }

    /// The deadline does not wait for a blocked filesystem syscall. Late results are ignored.
    public static func validate(_ locations: [MappedPath], timeout: TimeInterval = 8) async throws -> [URL] {
        guard timeout > 0 else { throw PathMappingError.timedOut }
        let ticket = AccessTicket()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ticket.start(continuation)
                queue.async {
                    guard ticket.isPending else { return }
                    ticket.finish(Result { try locations.map { try validate($0) } })
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + max(0, timeout)) {
                    ticket.finish(.failure(PathMappingError.timedOut))
                }
            }
        } onCancel: {
            ticket.finish(.failure(CancellationError()))
        }
    }
}

/// A cancellation/deadline and a filesystem result can race; only one resumes the caller.
private final class AccessTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[URL], any Error>?
    private var result: Result<[URL], any Error>?

    var isPending: Bool { lock.withLock { result == nil } }

    func start(_ continuation: CheckedContinuation<[URL], any Error>) {
        let completed = lock.withLock { () -> Result<[URL], any Error>? in
            if let result { return result }
            self.continuation = continuation
            return nil as Result<[URL], any Error>?
        }
        if let completed { continuation.resume(with: completed) }
    }

    func finish(_ result: Result<[URL], any Error>) {
        let waiting = lock.withLock {
            guard self.result == nil else { return nil as CheckedContinuation<[URL], any Error>? }
            self.result = result
            let waiting = continuation
            continuation = nil
            return waiting
        }
        waiting?.resume(with: result)
    }
}
