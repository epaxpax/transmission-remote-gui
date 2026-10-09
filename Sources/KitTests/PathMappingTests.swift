import Foundation
import TransmissionKit

func testPathMappings(_ t: TestHarness) async {
    print("\nPath mappings and Finder locations")
    let rules = [PathMapping(remotePath: "/srv/downloads", localPath: "/Volumes/Media")]
    func expectError(_ expected: PathMappingError, _ body: () throws -> Void) throws {
        var actual: PathMappingError?
        do { try body() } catch let error as PathMappingError { actual = error }
        try t.expectEqual(actual, expected)
    }
    func torrent(_ names: [String], directory: String = "/srv/downloads") throws -> Torrent {
        let files = names.map { ["name": $0, "length": 100, "bytesCompleted": 100] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["id": 7, "name": "Display name only",
            "downloadDir": directory, "files": files])
        return try JSONDecoder().decode(Torrent.self, from: data)
    }

    for folder in ["MT", "电影", "电视剧", "综艺", "其他", "资料"] {
        await t.test("Maps Chinese and ASCII share \(folder)") {
            let mapping = PathMapping(remotePath: "/srv/" + folder, localPath: "/Volumes/" + folder)
            let location = try PathMapping.resolve("/srv/" + folder + "/示例/片段 01.mkv", using: [mapping])
            try t.expectEqual(location.url.path, "/Volumes/" + folder + "/示例/片段 01.mkv")
        }
    }
    await t.test("Parses blank lines, CRLF, whitespace and a literal equals in local paths") {
        let parsed = try PathMapping.parse("\r\n /srv/电影/ = /Volumes/电影/ \r\n/srv/data=/Volumes/a=b\n")
        try t.expectEqual(parsed, [PathMapping(remotePath: "/srv/电影", localPath: "/Volumes/电影"),
                                  PathMapping(remotePath: "/srv/data", localPath: "/Volumes/a=b")])
        try t.expect(try PathMapping.parse("\n  \r\n").isEmpty, "empty text clears the mappings")
    }
    await t.test("Exact root and nested paths resolve without duplicate slashes") {
        try t.expectEqual(try PathMapping.resolve("/srv/downloads", using: rules).url.path, "/Volumes/Media")
        try t.expectEqual(try PathMapping.resolve("/srv//downloads///a/b/", using: rules).url.path, "/Volumes/Media/a/b")
    }
    await t.test("Directory matching cannot confuse MT with MT2") {
        try expectError(.noMapping) { _ = try PathMapping.resolve("/srv/downloads2/a", using: rules) }
    }
    await t.test("Remote POSIX paths retain case") {
        try expectError(.noMapping) { _ = try PathMapping.resolve("/SRV/downloads/a", using: rules) }
    }
    await t.test("Longest mapping wins independently of row order") {
        let child = PathMapping(remotePath: "/srv/downloads/special", localPath: "/Volumes/Special")
        for mappings in [rules + [child], [child] + rules] {
            try t.expectEqual(try PathMapping.resolve("/srv/downloads/special/a", using: mappings).url.path,
                              "/Volumes/Special/a")
        }
    }
    await t.test("A root mapping preserves the entire suffix") {
        try t.expectEqual(try PathMapping.resolve("/srv/a", using: [PathMapping(remotePath: "/", localPath: "/tmp/mapped")]).url.path,
                          "/tmp/mapped/srv/a")
    }
    await t.test("Duplicate normalized remote roots are rejected") {
        try expectError(.duplicateRemotePath) {
            _ = try PathMapping.parse("/srv/downloads=/tmp/a\n/srv/downloads/=/tmp/b")
        }
    }
    for bad in ["relative=/tmp/a", "/srv/a=relative", "/srv/../a=/tmp/a", "/srv/a=/tmp/./a", "/srv/a", "/srv/a=", "=/tmp/a"] {
        await t.test("Rejects malformed mapping \(bad)") {
            try expectError(.invalidMapping) { _ = try PathMapping.parse(bad) }
        }
    }
    for bad in ["relative/a", "/srv/downloads/../secret", "/srv/downloads/./a", "/srv/downloads/a\0b", "file:///srv/downloads/a"] {
        await t.test("Rejects invalid remote path \(bad.debugDescription)") {
            try expectError(.invalidRemotePath) { _ = try PathMapping.resolve(bad, using: rules) }
        }
    }
    await t.test("Percent, hash, quotes, dollar signs and filename whitespace remain literal") {
        let name = " 示例 #100% %2F = 'quoted' $(nothing).mkv "
        let url = try PathMapping.resolve("/srv/downloads/" + name, using: rules).url
        try t.expectEqual(url.lastPathComponent, name)
        try t.expectEqual(URL(string: url.absoluteString)?.path, url.path)
    }
    await t.test("Single file uses the real file path, not the torrent display name") {
        let item = try torrent(["renamed-file.mkv"])
        try t.expectEqual(try TorrentContentLocator.resolve(item, using: rules).url.path, "/Volumes/Media/renamed-file.mkv")
    }
    await t.test("A one-file torrent can still contain nested directories") {
        try t.expectEqual(try TorrentContentLocator.remotePath(for: torrent(["root/sub/file.mkv"])),
                          "/srv/downloads/root/sub/file.mkv")
    }
    await t.test("Multi-file torrents reveal the top-level root, not the deepest common directory") {
        try t.expectEqual(try TorrentContentLocator.remotePath(for: torrent(["root/sub/a", "root/sub/b"])),
                          "/srv/downloads/root")
    }
    await t.test("Flat or multiple-root torrents reveal downloadDir") {
        for paths in [["a", "b"], ["a/file", "b/file"], ["root", "root/file"]] {
            try t.expectEqual(try TorrentContentLocator.remotePath(for: torrent(paths)), "/srv/downloads")
        }
    }
    await t.test("Empty or absent magnet metadata produces a specific error") {
        try expectError(.metadataUnavailable) { _ = try TorrentContentLocator.remotePath(for: torrent([])) }
        var item = Torrent(id: 1); item.downloadDir = "/srv/downloads"
        try expectError(.metadataUnavailable) { _ = try TorrentContentLocator.remotePath(for: item) }
    }
    for name in ["../outside", "/absolute", "a/../b", "a//b", "a/./b", "", "a\0b"] {
        await t.test("Rejects invalid torrent file name \(name.debugDescription)") {
            try expectError(.invalidRemotePath) { _ = try TorrentContentLocator.remotePath(for: torrent([name])) }
        }
    }
    await t.test("A repeated torrent ID with a different hash is not the original target") {
        var a = Torrent(id: 1); a.hashString = "aaa"
        var b = Torrent(id: 1); b.hashString = "bbb"
        try t.expect(!TorrentContentLocator.matches(b, original: a), "ID reuse must not reveal unrelated content")
        try t.expect(TorrentContentLocator.matches(a, original: a), "same hash and id")
        b.id = 2; b.hashString = "aaa"
        try t.expect(!TorrentContentLocator.matches(b, original: a), "different id")
    }
    await t.test("Older server JSON decodes with no mappings and survives a round trip") {
        let original = ServerConfig(name: "Legacy", host: "example.invalid")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        try t.expect(decoded.pathMappings == nil, "missing key remains compatible")
        try t.expectEqual(decoded.id, original.id)
        try t.expectEqual(decoded.host, original.host)
    }
    await t.test("Mappings remain attached to their server across JSON persistence") {
        let a = ServerConfig(name: "A", pathMappings: rules)
        let b = ServerConfig(name: "B", pathMappings: [PathMapping(remotePath: "/srv/downloads", localPath: "/Volumes/Other")])
        let decoded = try JSONDecoder().decode([ServerConfig].self, from: JSONEncoder().encode([a, b]))
        try t.expectEqual(decoded[0].pathMappings, a.pathMappings)
        try t.expectEqual(decoded[1].pathMappings, b.pathMappings)
        try t.expect(decoded[0].pathMappings != decoded[1].pathMappings, "servers cannot share mapping state")
    }
    await t.test("Show in Finder needs downloadDir but does not require completion") {
        var item = Torrent(id: 1); item.downloadDir = "/srv/downloads"; item.percentDone = 0.1
        try t.expect(TorrentRowMenu.isEnabled(.showInFinder, for: [item]), "unfinished content can be revealed")
        try t.expect(!TorrentRowMenu.isEnabled(.showInFinder, for: [Torrent(id: 2)]), "missing directory")
        try t.expect(!TorrentRowMenu.isEnabled(.showInFinder, for: [item, Torrent(id: 2)]), "all selected targets need paths")
    }
    await t.test("Finder lookup only requests minimal torrent-get fields") {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _, _ in (200, [:], Data(#"{"result":"success","arguments":{"torrents":[]}}"#.utf8)) }
        let client = RPCClient(config: ServerConfig(), session: MockURLProtocol.makeSession())
        _ = try await client.torrentGet(fields: TorrentContentLocator.fields, ids: .ids([.id(7)]))
        let body = try t.unwrap(MockURLProtocol.lastBodies.last)
        let request = try t.unwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let args = try t.unwrap(request["arguments"] as? [String: Any])
        try t.expectEqual(request["method"] as? String, "torrent-get")
        try t.expectEqual(args["fields"] as? [String], ["id", "hashString", "downloadDir", "files"])
        try t.expectEqual(args["ids"] as? [Int], [7])
    }

    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PathMappingTests-" + UUID().uuidString)
    let root = temporary.appendingPathComponent("root")
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let file = root.appendingPathComponent("中文 #100% = 'quoted'.mkv")
        try Data("fixture".utf8).write(to: file)
        let fileLocation = MappedPath(url: file, localRoot: root)
        await t.test("Read-only filesystem validation accepts an existing file and directory") {
            try t.expectEqual(try LocalPathAccess.validate(fileLocation), file)
            try t.expectEqual(try LocalPathAccess.validate(MappedPath(url: root, localRoot: root)), root)
            try t.expectEqual(try Data(contentsOf: file), Data("fixture".utf8))
        }
        await t.test("Missing files are not mistaken for unmounted volumes") {
            try expectError(.notFound) { _ = try LocalPathAccess.validate(MappedPath(url: root.appendingPathComponent("missing"), localRoot: root)) }
        }
        await t.test("Missing files beneath a /private/tmp alias report absence, not an escape") {
            let parent = URL(fileURLWithPath: "/private/tmp/PathMappingAlias-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: parent) }
            try expectError(.notFound) {
                _ = try LocalPathAccess.validate(MappedPath(url: parent.appendingPathComponent("missing"), localRoot: parent))
            }
        }
        await t.test("A leftover /Volumes directory is not a mounted share") {
            let volume = URL(fileURLWithPath: "/Volumes/NotMountedTest")
            try expectError(.unmountedVolume) { _ = try LocalPathAccess.validate(MappedPath(url: volume, localRoot: volume), mountedVolumes: []) }
        }
        await t.test("A symlink cannot escape the mapped root") {
            let outside = temporary.appendingPathComponent("outside")
            try Data().write(to: outside)
            let link = root.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            try expectError(.outsideMapping) { _ = try LocalPathAccess.validate(MappedPath(url: link, localRoot: root)) }
        }
        await t.test("Unreadable files produce a permission error") {
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
            try expectError(.notReadable) { _ = try LocalPathAccess.validate(fileLocation) }
        }
        await t.test("Background validation returns the original Finder URL") {
            try t.expectEqual(try await LocalPathAccess.validate([fileLocation]), [file])
        }
        await t.test("An expired deadline does not start a filesystem probe") {
            var actual: PathMappingError?
            do { _ = try await LocalPathAccess.validate([fileLocation], timeout: 0) }
            catch let error as PathMappingError { actual = error }
            try t.expectEqual(actual, .timedOut)
        }
        await t.test("Cancelling a filesystem lookup resumes once without a late result") {
            let task = Task { try await LocalPathAccess.validate([fileLocation]) }
            task.cancel()
            var cancelled = false
            do { _ = try await task.value } catch is CancellationError { cancelled = true }
            try t.expect(cancelled, "cancelled action must not return a Finder location")
        }
    } catch {
        await t.test("Filesystem fixture setup") { throw error }
    }
}
