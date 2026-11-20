import Foundation
import TransmissionKit

func testWatchFolder(_ t: TestHarness) async {
    print("\nWatch folder")
    let fm = FileManager.default
    let start = ContinuousClock.now
    let bytes = Data("metainfo fixture".utf8)

    func withFolder(_ body: (URL) async throws -> Void) async throws {
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: folder) }
        try await body(folder)
    }

    await t.test("Existing servers decode with watching disabled, and configured paths round-trip") {
        var server = try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(ServerConfig()))
        try t.expectEqual(server.watchFolderPath, nil)
        server.watchFolderPath = "/tmp/Torrents"
        try t.expectEqual(try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(server)), server)
    }

    await t.test("Automatic adding inherits the daemon's download location and start preference") {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _, _ in
            (200, [:], Data(#"{"result":"success","arguments":{"torrent-duplicate":{"id":1}}}"#.utf8))
        }
        let client = makeClient()
        let duplicate = try await client.torrentAdd(metainfoBase64: bytes.base64EncodedString(), paused: nil)
        try t.expect(duplicate.isDuplicate, "an existing torrent counts as received")
        _ = try await client.torrentAdd(metainfoBase64: bytes.base64EncodedString())
        let requests = try MockURLProtocol.lastBodies.map {
            try t.unwrap(try JSONSerialization.jsonObject(with: $0) as? [String: Any])
        }
        let automatic = try t.unwrap(requests[0]["arguments"] as? [String: Any])
        let manual = try t.unwrap(requests[1]["arguments"] as? [String: Any])
        try t.expectEqual(requests[0]["method"] as? String, "torrent-add")
        try t.expectEqual(Set(automatic.keys), ["metainfo"])
        try t.expectEqual(manual["paused"] as? Bool, false)
    }

    await t.test("Waits for a stable copy and only imports top-level torrent files") {
        try await withFolder { folder in
            let source = folder.appendingPathComponent("example.TORRENT")
            let marked = source.appendingPathExtension("added")
            let nested = folder.appendingPathComponent("nested.torrent", isDirectory: true)
            try fm.createDirectory(at: nested, withIntermediateDirectories: false)
            try bytes.write(to: nested.appendingPathComponent("inside.torrent"))
            try bytes.write(to: folder.appendingPathComponent("old.torrent.added"))
            try bytes.write(to: folder.appendingPathComponent("copy.torrent.part"))
            try fm.createSymbolicLink(at: folder.appendingPathComponent("link.torrent"),
                                      withDestinationURL: nested.appendingPathComponent("inside.torrent"))
            try Data([1]).write(to: source)
            var importer = WatchFolderImporter(folder: folder)
            var submissions: [String] = []
            func submit(_ metainfo: String) -> Bool {
                submissions.append(metainfo)
                return true
            }
            await importer.scan(now: start, submit: submit)
            try bytes.write(to: source)
            await importer.scan(now: start + .seconds(2), submit: submit)
            try t.expect(submissions.isEmpty, "an in-progress copy must not be sent")
            await importer.scan(now: start + .seconds(4), submit: submit)
            await importer.scan(now: start + .seconds(6), submit: submit)
            try t.expectEqual(submissions, [bytes.base64EncodedString()])
            try t.expectEqual(try Data(contentsOf: marked), bytes)
            try t.expect(!fm.fileExists(atPath: source.path), "successful import should rename the input")
        }
    }

    await t.test("Retries a failed submission and preserves the file until acknowledged") {
        try await withFolder { folder in
            let source = folder.appendingPathComponent("pending.torrent")
            try bytes.write(to: source)
            var importer = WatchFolderImporter(folder: folder)
            var calls = 0
            func submit(_ metainfo: String) throws -> Bool {
                calls += 1
                if calls == 1 { throw URLError(.notConnectedToInternet) }
                if calls == 2 { return false }
                return true
            }
            await importer.scan(now: start, submit: submit)
            await importer.scan(now: start + .seconds(2), submit: submit)
            await importer.scan(now: start + .seconds(4), submit: submit)
            try t.expectEqual(calls, 1)
            try t.expectEqual(try Data(contentsOf: source), bytes)
            await importer.scan(now: start + .seconds(32), submit: submit)
            try t.expectEqual(try Data(contentsOf: source), bytes)
            await importer.scan(now: start + .seconds(62), submit: submit)
            try t.expectEqual(calls, 3)
            try t.expectEqual(try Data(contentsOf: source.appendingPathExtension("added")), bytes)
        }
    }

    await t.test("A replaced file is imported separately and existing markers are preserved") {
        try await withFolder { folder in
            let source = folder.appendingPathComponent("reused.torrent")
            let oldMarker = source.appendingPathExtension("added")
            let newMarker = folder.appendingPathComponent("reused.2.torrent.added")
            let original = Data([0])
            try original.write(to: oldMarker)
            try original.write(to: source)
            var importer = WatchFolderImporter(folder: folder)
            await importer.scan(now: start) { _ in true }
            await importer.scan(now: start + .seconds(2)) { _ in
                try bytes.write(to: source, options: .atomic)
                return true
            }
            try t.expectEqual(try Data(contentsOf: source), bytes)
            await importer.scan(now: start + .seconds(4)) { _ in true }
            await importer.scan(now: start + .seconds(6)) { $0 == bytes.base64EncodedString() }
            try t.expectEqual(try Data(contentsOf: oldMarker), original)
            try t.expectEqual(try Data(contentsOf: newMarker), bytes)
        }
    }

    await t.test("A permanent daemon rejection is marked invalid without resubmission") {
        try await withFolder { folder in
            let source = folder.appendingPathComponent("corrupt.torrent")
            let marked = source.appendingPathExtension("invalid")
            try bytes.write(to: source)
            var importer = WatchFolderImporter(folder: folder)
            var calls = 0
            func submit(_ metainfo: String) throws -> Bool {
                calls += 1
                if calls == 1 { throw RPCError.rpcFailure("temporarily unavailable") }
                throw RPCError.rpcFailure("invalid or corrupt torrent file")
            }
            await importer.scan(now: start, submit: submit)
            await importer.scan(now: start + .seconds(2), submit: submit)
            try t.expect(fm.fileExists(atPath: source.path), "an unknown RPC failure must keep the source")
            await importer.scan(now: start + .seconds(32), submit: submit)
            await importer.scan(now: start + .seconds(70), submit: submit)
            try t.expectEqual(calls, 2)
            try t.expectEqual(try Data(contentsOf: marked), bytes)
            try t.expect(!fm.fileExists(atPath: source.path), "the invalid marker must replace the source name")
        }
    }

    await t.test("The size cap skips oversized files and accepts the exact limit") {
        try await withFolder { folder in
            let limit = WatchFolderImporter.maximumFileSize
            let oversized = folder.appendingPathComponent("big.torrent")
            let boundary = folder.appendingPathComponent("limit.torrent")
            func create(_ url: URL, size: Int) throws {
                try Data().write(to: url)
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.truncate(atOffset: UInt64(size))
            }
            try create(oversized, size: limit + 1)
            try create(boundary, size: limit)
            var importer = WatchFolderImporter(folder: folder)
            var calls = 0
            func submit(_ metainfo: String) throws -> Bool {
                calls += 1
                try t.expectEqual(Data(base64Encoded: metainfo)?.count, limit)
                return true
            }
            let first = await importer.scan(now: start, submit: submit)
            let later = await importer.scan(now: start + .seconds(2), submit: submit)
            try t.expectEqual(first, .fileTooLarge("big.torrent"))
            try t.expectEqual(later, first)
            try t.expectEqual(calls, 1)
            try t.expect(fm.fileExists(atPath: oversized.path), "oversized files are left intact")
            try t.expect(fm.fileExists(atPath: boundary.appendingPathExtension("added").path), "exact limit is allowed")
        }
    }

    await t.test("Folder access errors are reported and clear after recovery") {
        try await withFolder { root in
            let folder = root.appendingPathComponent("pending", isDirectory: true)
            var importer = WatchFolderImporter(folder: folder)
            let missing = await importer.scan(now: start) { _ in false }
            try t.expectEqual(missing, .cannotReadFolder)
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            let recovered = await importer.scan(now: start + .seconds(2)) { _ in false }
            try t.expectEqual(recovered, nil)
        }
    }

    await t.test("A failed invalid rename is reported and retried without another RPC") {
        try await withFolder { folder in
            let source = folder.appendingPathComponent("denied.torrent")
            try bytes.write(to: source)
            defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
            var importer = WatchFolderImporter(folder: folder)
            var calls = 0
            func submit(_ metainfo: String) throws -> Bool {
                calls += 1
                try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
                throw RPCError.rpcFailure("invalid or corrupt torrent file")
            }
            await importer.scan(now: start, submit: submit)
            let denied = await importer.scan(now: start + .seconds(2), submit: submit)
            try t.expectEqual(denied, .cannotRenameFile("denied.torrent"))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            let recovered = await importer.scan(now: start + .seconds(32), submit: submit)
            try t.expectEqual(recovered, nil)
            try t.expectEqual(calls, 1)
            try t.expectEqual(try Data(contentsOf: source.appendingPathExtension("invalid")), bytes)
        }
    }

}
