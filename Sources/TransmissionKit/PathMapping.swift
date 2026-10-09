import Foundation

/// A manually configured POSIX daemon directory and its locally mounted counterpart.
/// These are paths, not URLs: percent signs and other filename characters stay literal.
public struct PathMapping: Codable, Hashable, Sendable {
    public var remotePath: String
    public var localPath: String

    public init(remotePath: String, localPath: String) {
        self.remotePath = remotePath
        self.localPath = localPath
    }

    /// Parses the classic transgui `remote=local` format, one rule per line.
    public static func parse(_ text: String) throws -> [PathMapping] {
        let rows = try text.components(separatedBy: .newlines).compactMap { line -> PathMapping? in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            guard let separator = line.firstIndex(of: "=") else { throw PathMappingError.invalidMapping }
            return PathMapping(remotePath: String(line[..<separator]),
                               localPath: String(line[line.index(after: separator)...]))
        }
        return try validated(rows)
    }

    /// Validates all rows before saving: an invalid or ambiguous rule is never ignored.
    public static func validated(_ mappings: [PathMapping]) throws -> [PathMapping] {
        var seen = Set<String>()
        return try mappings.map { mapping in
            guard let remote = absolutePath(mapping.remotePath.trimmingCharacters(in: .whitespaces)),
                  let local = absolutePath(mapping.localPath.trimmingCharacters(in: .whitespaces))
            else { throw PathMappingError.invalidMapping }
            guard seen.insert(remote).inserted else { throw PathMappingError.duplicateRemotePath }
            return PathMapping(remotePath: remote, localPath: local)
        }
    }

    /// Longest directory-boundary match wins; rule order cannot shadow a child mapping.
    public static func resolve(_ remotePath: String, using mappings: [PathMapping]) throws -> MappedPath {
        guard let path = absolutePath(remotePath) else { throw PathMappingError.invalidRemotePath }
        let rules = try validated(mappings)
        let matches = rules.filter { contains(path, in: $0.remotePath) }
        guard let rule = matches.max(by: { $0.remotePath.count < $1.remotePath.count })
        else { throw PathMappingError.noMapping }
        let suffix = path.dropFirst(rule.remotePath == "/" ? 1 : rule.remotePath.count)
        let root = URL(fileURLWithPath: rule.localPath, isDirectory: true)
        let url = suffix.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
        return MappedPath(url: url, localRoot: root)
    }

    static func contains(_ path: String, in root: String) -> Bool {
        root == "/" || path == root || path.hasPrefix(root + "/")
    }

    static func absolutePath(_ path: String) -> String? {
        guard path.hasPrefix("/"), !hasControlCharacters(path) else { return nil }
        let components = path.split(separator: "/")
        guard !components.contains("."), !components.contains("..") else { return nil }
        return "/" + components.joined(separator: "/")
    }

    static func hasControlCharacters(_ path: String) -> Bool {
        path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

public struct MappedPath: Hashable, Sendable {
    public let url: URL
    public let localRoot: URL

    public init(url: URL, localRoot: URL) {
        self.url = url
        self.localRoot = localRoot
    }
}

public enum PathMappingError: Error, Equatable, Sendable {
    case invalidMapping
    case duplicateRemotePath
    case invalidRemotePath
    case noMapping
    case metadataUnavailable
    case contentChanged
    case unmountedVolume
    case notFound
    case notReadable
    case outsideMapping
    case timedOut
}

/// Uses the daemon's file paths, not the torrent's editable display name.
public enum TorrentContentLocator {
    public static let fields = ["id", "hashString", "downloadDir", "files"]

    public static func remotePath(for torrent: Torrent) throws -> String {
        guard let rawDirectory = torrent.downloadDir,
              let directory = PathMapping.absolutePath(rawDirectory)
        else { throw PathMappingError.invalidRemotePath }
        guard let files = torrent.files, !files.isEmpty else { throw PathMappingError.metadataUnavailable }
        let paths = try files.map { file -> [String] in
            guard !file.name.isEmpty, !file.name.hasPrefix("/"),
                  !PathMapping.hasControlCharacters(file.name) else { throw PathMappingError.invalidRemotePath }
            let parts = file.name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
            else { throw PathMappingError.invalidRemotePath }
            return parts
        }
        let base = directory == "/" ? "" : directory
        if paths.count == 1 { return base + "/" + paths[0].joined(separator: "/") }
        // Reveal the torrent's top-level folder, not an arbitrary deeply nested file.
        if let root = paths[0].first, paths.allSatisfy({ $0.count > 1 && $0.first == root }) {
            return base + "/" + root
        }
        return directory  // Files stored directly in downloadDir have no torrent root folder.
    }

    public static func resolve(_ torrent: Torrent, using mappings: [PathMapping]) throws -> MappedPath {
        try PathMapping.resolve(remotePath(for: torrent), using: mappings)
    }

    /// A removed/re-added torrent must not silently reuse an earlier context menu's ID.
    public static func matches(_ current: Torrent, original: Torrent) -> Bool {
        current.id == original.id && (original.hashString == nil || current.hashString == original.hashString)
    }
}
