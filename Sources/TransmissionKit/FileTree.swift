import Foundation

/// One row of the hierarchical Files tab: a directory (aggregated over its descendants)
/// or a single file. Node ids are derived from the relative path, so the identity — and
/// with it the expanded state — survives the periodic detail refreshes.
public struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// Checkbox state of a directory: all, none or some of its files are wanted.
    public enum CheckState: Hashable, Sendable { case on, off, mixed }
    /// Priority of a directory: the common priority of its files, or mixed.
    public enum PriorityState: Hashable, Sendable {
        case uniform(TorrentFileStat.Priority)
        case mixed
    }

    /// Stable identity. Directories end with "/" so they never collide with a file id.
    public let id: String
    /// Path relative to the torrent's download directory, without a trailing slash.
    public let path: String
    public let name: String
    /// 0 for top-level entries.
    public let depth: Int
    /// Index into `files` / `fileStats`; `nil` for directories.
    public let fileIndex: Int?
    /// Sorted: directories first, then files, by Finder-like name order. Empty for files.
    public let children: [FileTreeNode]
    /// Every file index below this node (the file itself for a file), ascending.
    public let fileIndices: [Int]
    public let length: Int
    public let bytesCompleted: Int
    /// `nil` when the daemon sent no `fileStats` for (some of) the files.
    public let wanted: CheckState?
    public let priority: PriorityState?

    public var isDirectory: Bool { fileIndex == nil }

    public var progress: Double {
        guard length > 0 else { return 0 }
        return min(1, Double(bytesCompleted) / Double(length))
    }
}

public enum FileTree {
    /// Builds the tree from the flat, index-aligned `files` / `fileStats` arrays.
    /// Works for single-file torrents and for files stored directly in the root.
    public static func build(files: [TorrentFile], stats: [TorrentFileStat]?) -> [FileTreeNode] {
        let root = Builder()
        var usedFileIDs = Set<String>()
        for (index, file) in files.enumerated() {
            var parts = file.name.split(separator: "/").map(String.init)
            if parts.isEmpty { parts = [file.name] }
            var node = root
            for part in parts.dropLast() {
                node = node.directory(part)
            }
            let path = parts.joined(separator: "/")
            // Duplicate paths should not occur, but SwiftUI ids must stay unique.
            var id = path
            if usedFileIDs.contains(id) { id = path + "#\(index)" }
            usedFileIDs.insert(id)
            node.files.append(FileEntry(id: id, path: path, name: parts.last ?? file.name, index: index,
                                        length: file.length, bytesCompleted: file.bytesCompleted,
                                        stat: stats.flatMap { index < $0.count ? $0[index] : nil }))
        }
        return root.nodes(prefix: "", depth: 0)
    }

    /// The rows to show, in display order: a directory's children only when it is expanded.
    public static func visibleRows(_ roots: [FileTreeNode], expanded: Set<String>) -> [FileTreeNode] {
        var rows: [FileTreeNode] = []
        func walk(_ nodes: [FileTreeNode]) {
            for node in nodes {
                rows.append(node)
                if node.isDirectory, expanded.contains(node.id) { walk(node.children) }
            }
        }
        walk(roots)
        return rows
    }

    /// Initial expanded state: a torrent's single top-level folder is opened, so the common
    /// "one folder with files" layout does not start as a lone collapsed row.
    public static func defaultExpanded(_ roots: [FileTreeNode]) -> Set<String> {
        guard roots.count == 1, let only = roots.first, only.isDirectory else { return [] }
        return [only.id]
    }

    /// Ids of every directory in the tree (e.g. to drop stale expanded ids).
    public static func directoryIDs(_ roots: [FileTreeNode]) -> Set<String> {
        var ids = Set<String>()
        func walk(_ nodes: [FileTreeNode]) {
            for node in nodes where node.isDirectory {
                ids.insert(node.id)
                walk(node.children)
            }
        }
        walk(roots)
        return ids
    }

    /// One `torrent-set` call that (un)selects all given files.
    public static func wantedArgs(torrentID: Int, indices: [Int], wanted: Bool) -> TorrentSetArgs {
        var args = TorrentSetArgs(ids: .ids([.id(torrentID)]))
        if wanted { args.filesWanted = indices } else { args.filesUnwanted = indices }
        return args
    }

    /// One `torrent-set` call that sets the priority of all given files.
    public static func priorityArgs(torrentID: Int, indices: [Int],
                                    priority: TorrentFileStat.Priority) -> TorrentSetArgs {
        var args = TorrentSetArgs(ids: .ids([.id(torrentID)]))
        switch priority {
        case .low: args.priorityLow = indices
        case .normal: args.priorityNormal = indices
        case .high: args.priorityHigh = indices
        }
        return args
    }

    // MARK: - Building

    private struct FileEntry {
        let id: String
        let path: String
        let name: String
        let index: Int
        let length: Int
        let bytesCompleted: Int
        let stat: TorrentFileStat?
    }

    private final class Builder {
        var directories: [String: Builder] = [:]
        var files: [FileEntry] = []

        func directory(_ name: String) -> Builder {
            if let existing = directories[name] { return existing }
            let created = Builder()
            directories[name] = created
            return created
        }

        func nodes(prefix: String, depth: Int) -> [FileTreeNode] {
            let order: (String, String) -> Bool = {
                let result = $0.localizedStandardCompare($1)
                return result == .orderedSame ? $0 < $1 : result == .orderedAscending
            }
            let dirs = directories.keys.sorted(by: order).map { name -> FileTreeNode in
                let path = prefix + name
                let children = directories[name]!.nodes(prefix: path + "/", depth: depth + 1)
                return FileTree.directoryNode(path: path, name: name, depth: depth, children: children)
            }
            let leaves = files.sorted { order($0.name, $1.name) || ($0.name == $1.name && $0.index < $1.index) }
                .map { file in
                    FileTreeNode(id: file.id, path: file.path, name: file.name, depth: depth,
                                 fileIndex: file.index, children: [], fileIndices: [file.index],
                                 length: file.length, bytesCompleted: file.bytesCompleted,
                                 wanted: file.stat.map { $0.wanted ? .on : .off },
                                 priority: file.stat.map { .uniform($0.priorityValue) })
                }
            return dirs + leaves
        }
    }

    private static func directoryNode(path: String, name: String, depth: Int,
                                      children: [FileTreeNode]) -> FileTreeNode {
        var wanted: FileTreeNode.CheckState?
        var priority: FileTreeNode.PriorityState?
        var unknown = false
        for (offset, child) in children.enumerated() {
            guard let childWanted = child.wanted, let childPriority = child.priority else {
                unknown = true
                break
            }
            if offset == 0 {
                wanted = childWanted
                priority = childPriority
            } else {
                if wanted != childWanted { wanted = .mixed }
                if priority != childPriority { priority = .mixed }
            }
        }
        if unknown || children.isEmpty {
            wanted = nil
            priority = nil
        }
        return FileTreeNode(id: path + "/", path: path, name: name, depth: depth, fileIndex: nil,
                            children: children,
                            fileIndices: children.flatMap(\.fileIndices).sorted(),
                            length: children.reduce(0) { $0 + $1.length },
                            bytesCompleted: children.reduce(0) { $0 + $1.bytesCompleted },
                            wanted: wanted, priority: priority)
    }
}

public extension TorrentContentLocator {
    /// Daemon-side path of a file or folder inside the torrent (`entry` is a node's `path`).
    /// The entry must still exist in the torrent's current file list.
    static func remotePath(for torrent: Torrent, entry: String) throws -> String {
        guard let rawDirectory = torrent.downloadDir,
              let directory = PathMapping.absolutePath(rawDirectory)
        else { throw PathMappingError.invalidRemotePath }
        guard let files = torrent.files, !files.isEmpty else { throw PathMappingError.metadataUnavailable }
        let parts = entry.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !entry.isEmpty, !PathMapping.hasControlCharacters(entry),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw PathMappingError.invalidRemotePath }
        guard files.contains(where: { $0.name == entry || $0.name.hasPrefix(entry + "/") })
        else { throw PathMappingError.contentChanged }
        return (directory == "/" ? "" : directory) + "/" + entry
    }

    static func resolve(_ torrent: Torrent, entry: String, using mappings: [PathMapping]) throws -> MappedPath {
        try PathMapping.resolve(remotePath(for: torrent, entry: entry), using: mappings)
    }
}
