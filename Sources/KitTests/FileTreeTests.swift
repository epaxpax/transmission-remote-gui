import Foundation
import TransmissionKit

func testFileTree(_ t: TestHarness) async {
    print("\nHierarchical file tree")
    // The models only have a decoding initializer, like the daemon's JSON.
    func decode<T: Decodable>(_ object: [String: Any]) -> T {
        try! JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func file(_ name: String, _ length: Int = 100, done: Int = 0) -> TorrentFile {
        decode(["name": name, "length": length, "bytesCompleted": done])
    }
    func stat(_ wanted: Bool = true, _ priority: Int = 0) -> TorrentFileStat {
        decode(["bytesCompleted": 0, "wanted": wanted, "priority": priority])
    }
    func find(_ id: String, in nodes: [FileTreeNode]) -> FileTreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let hit = find(id, in: node.children) { return hit }
        }
        return nil
    }
    func torrent(_ names: [String], directory: String = "/srv/downloads") throws -> Torrent {
        let files = names.map { ["name": $0, "length": 100, "bytesCompleted": 100] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["id": 3, "downloadDir": directory, "files": files])
        return try JSONDecoder().decode(Torrent.self, from: data)
    }

    let files = [
        file("Show/S01/e02.mkv", 300, done: 300),
        file("Show/S01/e01.mkv", 100, done: 50),
        file("Show/Extras/info.nfo", 10, done: 10),
        file("Show/S01/e10.mkv", 100),
    ]
    let stats = [stat(true, 1), stat(true, 1), stat(false, 0), stat(true, 1)]

    await t.test("Builds nested folders with path ids, folders first, natural name order") {
        let roots = FileTree.build(files: files, stats: stats)
        try t.expectEqual(roots.map(\.id), ["Show/"])
        let show = try t.unwrap(roots.first)
        try t.expectEqual(show.children.map(\.id), ["Show/Extras/", "Show/S01/"])
        let season = try t.unwrap(find("Show/S01/", in: roots))
        try t.expectEqual(season.children.map(\.name), ["e01.mkv", "e02.mkv", "e10.mkv"])
        try t.expectEqual(season.children.map(\.fileIndex), [1, 0, 3])
        try t.expectEqual(season.children.map(\.depth), [2, 2, 2])
        try t.expectEqual(season.path, "Show/S01")
        try t.expect(season.isDirectory && !season.children[0].isDirectory, "directory vs file")
    }
    await t.test("Aggregates size, progress and descendant indices per folder") {
        let roots = FileTree.build(files: files, stats: stats)
        let show = try t.unwrap(roots.first)
        try t.expectEqual(show.length, 510)
        try t.expectEqual(show.bytesCompleted, 360)
        try t.expectEqual(show.fileIndices, [0, 1, 2, 3])
        let season = try t.unwrap(find("Show/S01/", in: roots))
        try t.expectEqual(season.fileIndices, [0, 1, 3])
        try t.expectEqual(season.progress, 350.0 / 500.0)
    }
    await t.test("Wanted and priority are uniform or mixed per folder") {
        let roots = FileTree.build(files: files, stats: stats)
        let season = try t.unwrap(find("Show/S01/", in: roots))
        try t.expectEqual(season.wanted, .on)
        try t.expectEqual(season.priority, .uniform(.high))
        let extras = try t.unwrap(find("Show/Extras/", in: roots))
        try t.expectEqual(extras.wanted, .off)
        try t.expectEqual(extras.priority, .uniform(.normal))
        let show = try t.unwrap(roots.first)
        try t.expectEqual(show.wanted, .mixed)
        try t.expectEqual(show.priority, .mixed)
    }
    await t.test("Mixed state propagates through a folder whose own children are uniform") {
        let roots = FileTree.build(files: [file("A/B/x"), file("A/B/y"), file("A/z")],
                                   stats: [stat(true, -1), stat(false, -1), stat(true, -1)])
        try t.expectEqual(find("A/B/", in: roots)?.wanted, .mixed)
        try t.expectEqual(find("A/", in: roots)?.wanted, .mixed)
        try t.expectEqual(find("A/", in: roots)?.priority, .uniform(.low))
    }
    await t.test("Missing fileStats leave wanted/priority unknown") {
        let roots = FileTree.build(files: files, stats: nil)
        try t.expectEqual(roots.first?.wanted, nil)
        try t.expectEqual(roots.first?.priority, nil)
        let partial = FileTree.build(files: files, stats: Array(stats.prefix(2)))
        try t.expectEqual(find("Show/S01/", in: partial)?.wanted, nil)
        try t.expectEqual(find("Show/Extras/", in: partial)?.wanted, nil)
    }
    await t.test("Single-file torrent is one root file row") {
        let roots = FileTree.build(files: [file("movie.mkv", 42, done: 21)], stats: [stat()])
        try t.expectEqual(roots.map(\.id), ["movie.mkv"])
        try t.expectEqual(roots.first?.fileIndex, 0)
        try t.expectEqual(roots.first?.progress, 0.5)
        try t.expectEqual(FileTree.defaultExpanded(roots), [])
        try t.expectEqual(FileTree.visibleRows(roots, expanded: []).map(\.id), ["movie.mkv"])
    }
    await t.test("Files directly in the root sit next to folders") {
        let roots = FileTree.build(files: [file("b.txt"), file("dir/c.txt"), file("a.txt")],
                                   stats: [stat(), stat(), stat()])
        try t.expectEqual(roots.map(\.id), ["dir/", "a.txt", "b.txt"])
        try t.expectEqual(roots.map(\.depth), [0, 0, 0])
        try t.expectEqual(FileTree.defaultExpanded(roots), [])
    }
    await t.test("A file and a folder with the same name get distinct ids") {
        let roots = FileTree.build(files: [file("x"), file("x/y"), file("x")], stats: nil)
        try t.expectEqual(roots.map(\.id), ["x/", "x", "x#2"])
    }
    await t.test("Visible rows follow the expanded set; default opens a lone root folder") {
        let roots = FileTree.build(files: files, stats: stats)
        try t.expectEqual(FileTree.defaultExpanded(roots), ["Show/"])
        try t.expectEqual(FileTree.visibleRows(roots, expanded: []).map(\.id), ["Show/"])
        try t.expectEqual(FileTree.visibleRows(roots, expanded: ["Show/"]).map(\.id),
                          ["Show/", "Show/Extras/", "Show/S01/"])
        // A collapsed parent hides an expanded child.
        try t.expectEqual(FileTree.visibleRows(roots, expanded: ["Show/S01/"]).map(\.id), ["Show/"])
        try t.expectEqual(FileTree.visibleRows(roots, expanded: ["Show/", "Show/S01/"]).map(\.id),
                          ["Show/", "Show/Extras/", "Show/S01/", "Show/S01/e01.mkv",
                           "Show/S01/e02.mkv", "Show/S01/e10.mkv"])
        try t.expectEqual(FileTree.directoryIDs(roots), ["Show/", "Show/Extras/", "Show/S01/"])
    }
    await t.test("Ids are stable when progress and stats change between refreshes") {
        let before = FileTree.build(files: files, stats: stats)
        var later = files
        later[1] = file("Show/S01/e01.mkv", 100, done: 100)
        let after = FileTree.build(files: later, stats: stats.map { _ in stat(false, -1) })
        try t.expectEqual(FileTree.visibleRows(before, expanded: FileTree.directoryIDs(before)).map(\.id),
                          FileTree.visibleRows(after, expanded: FileTree.directoryIDs(after)).map(\.id))
    }
    await t.test("One torrent-set call for all descendant files") {
        let roots = FileTree.build(files: files, stats: stats)
        let season = try t.unwrap(find("Show/S01/", in: roots))
        let wanted = FileTree.wantedArgs(torrentID: 9, indices: season.fileIndices, wanted: false)
        let json = try t.unwrap(String(data: try JSONEncoder().encode(wanted), encoding: .utf8))
        try t.expect(json.contains("\"files-unwanted\":[0,1,3]"), json)
        try t.expect(!json.contains("files-wanted"), json)
        let priority = FileTree.priorityArgs(torrentID: 9, indices: season.fileIndices, priority: .low)
        try t.expectEqual(priority.priorityLow, [0, 1, 3])
        try t.expectEqual(priority.priorityHigh, nil)
        try t.expectEqual(FileTree.wantedArgs(torrentID: 9, indices: [2], wanted: true).filesWanted, [2])
        try t.expectEqual(FileTree.priorityArgs(torrentID: 9, indices: [2], priority: .high).priorityHigh, [2])
    }
    await t.test("Remote path of a file or folder entry inside the torrent") {
        let tor = try torrent(["Show/S01/e01.mkv", "Show/a.nfo"])
        try t.expectEqual(try TorrentContentLocator.remotePath(for: tor, entry: "Show/S01/e01.mkv"),
                          "/srv/downloads/Show/S01/e01.mkv")
        try t.expectEqual(try TorrentContentLocator.remotePath(for: tor, entry: "Show/S01"),
                          "/srv/downloads/Show/S01")
        let rootDir = try torrent(["movie.mkv"], directory: "/")
        try t.expectEqual(try TorrentContentLocator.remotePath(for: rootDir, entry: "movie.mkv"), "/movie.mkv")
        let mapped = try TorrentContentLocator.resolve(tor, entry: "Show/S01",
            using: [PathMapping(remotePath: "/srv/downloads", localPath: "/Volumes/Media")])
        try t.expectEqual(mapped.url.path, "/Volumes/Media/Show/S01")
    }
    await t.test("Remote entry path rejects traversal, prefixes and vanished entries") {
        let tor = try torrent(["Show/S01/e01.mkv"])
        for bad in ["", "Show/../x", "./Show", "Show//S01", "/Show"] {
            var error: PathMappingError?
            do { _ = try TorrentContentLocator.remotePath(for: tor, entry: bad) }
            catch let e as PathMappingError { error = e }
            try t.expectEqual(error, .invalidRemotePath)
        }
        for gone in ["Sho", "Show/S0", "Other"] {
            var error: PathMappingError?
            do { _ = try TorrentContentLocator.remotePath(for: tor, entry: gone) }
            catch let e as PathMappingError { error = e }
            try t.expectEqual(error, .contentChanged)
        }
    }
}
