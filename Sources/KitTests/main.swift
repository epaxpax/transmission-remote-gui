import Foundation
import TransmissionKit

let t = TestHarness()

func makeClient() -> RPCClient {
    let config = ServerConfig(host: "127.0.0.1", port: 9091)
    return RPCClient(config: config, session: MockURLProtocol.makeSession())
}

print("RPCClient")

await t.test("Resends the request with the session id after the 409 handshake") {
    MockURLProtocol.reset()
    let successBody = #"{"result":"success","arguments":{"torrents":[{"id":1,"name":"A"}]},"tag":0}"#.data(using: .utf8)!
    MockURLProtocol.handler = { request, count in
        if count == 1 {
            try? t.expect(request.value(forHTTPHeaderField: "X-Transmission-Session-Id") == nil, "no session id on the first call")
            return (409, ["X-Transmission-Session-Id": "TOKEN-123"], Data())
        } else {
            try? t.expect(request.value(forHTTPHeaderField: "X-Transmission-Session-Id") == "TOKEN-123", "the session id must be sent back")
            return (200, [:], successBody)
        }
    }
    let torrents = try await makeClient().torrentGet()
    try t.expectEqual(MockURLProtocol.requestCount, 2)
    try t.expectEqual(torrents.count, 1)
    try t.expectEqual(torrents.first?.name, "A")
}

await t.test("The request envelope has method/arguments/tag format") {
    MockURLProtocol.reset()
    let successBody = #"{"result":"success","arguments":{"torrents":[]},"tag":0}"#.data(using: .utf8)!
    MockURLProtocol.handler = { _, _ in (200, [:], successBody) }
    _ = try await makeClient().torrentGet(fields: ["id", "name"], ids: .ids([.id(7)]))
    let body = try t.unwrap(MockURLProtocol.lastBodies.last)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    try t.expectEqual(json["method"] as? String, "torrent-get")
    let args = try t.unwrap(json["arguments"] as? [String: Any])
    try t.expectEqual(args["fields"] as? [String], ["id", "name"])
    try t.expectEqual(args["format"] as? String, "objects")
    try t.expectEqual(args["ids"] as? [Int], [7])
}

await t.test("No ids key is sent for .all") {
    MockURLProtocol.reset()
    let successBody = #"{"result":"success","arguments":{"torrents":[]},"tag":0}"#.data(using: .utf8)!
    MockURLProtocol.handler = { _, _ in (200, [:], successBody) }
    _ = try await makeClient().torrentGet(ids: .all)
    let body = try t.unwrap(MockURLProtocol.lastBodies.last)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let args = try t.unwrap(json["arguments"] as? [String: Any])
    try t.expect(args["ids"] == nil, "the ids key must not be present")
}

await t.test("A non-success result throws an error") {
    MockURLProtocol.reset()
    let body = #"{"result":"invalid argument","arguments":{},"tag":0}"#.data(using: .utf8)!
    MockURLProtocol.handler = { _, _ in (200, [:], body) }
    var threw = false
    do { _ = try await makeClient().torrentGet() } catch is RPCError { threw = true }
    try t.expect(threw, "it should have thrown an RPCError")
}

await t.test("A 401 results in an unauthorized error") {
    MockURLProtocol.reset()
    MockURLProtocol.handler = { _, _ in (401, [:], Data()) }
    var threw = false
    do { _ = try await makeClient().torrentGet() } catch is RPCError { threw = true }
    try t.expect(threw, "it should have thrown an RPCError")
}

print("\nModel decoding")

await t.test("Torrent decoding from camelCase fields") {
    let json = #"{"id":42,"name":"Ubuntu ISO","status":4,"percentDone":0.5,"rateDownload":1024,"uploadRatio":1.25,"peersConnected":3,"addedDate":1700000000,"error":0}"#.data(using: .utf8)!
    let torrent = try JSONDecoder().decode(Torrent.self, from: json)
    try t.expectEqual(torrent.id, 42)
    try t.expectEqual(torrent.displayName, "Ubuntu ISO")
    try t.expect(torrent.statusValue == .downloading, "downloading status")
    try t.expectEqual(torrent.progress, 0.5)
    try t.expectEqual(torrent.downloadRate, 1024)
    try t.expectEqual(torrent.ratio, 1.25)
    try t.expectEqual(torrent.connectedPeers, 3)
    try t.expect(!torrent.hasError, "there should be no error")
    try t.expect(torrent.addedDateValue != nil, "there should be an added date")
}

await t.test("Default values for missing fields") {
    let json = #"{"id":1}"#.data(using: .utf8)!
    let torrent = try JSONDecoder().decode(Torrent.self, from: json)
    try t.expectEqual(torrent.id, 1)
    try t.expectEqual(torrent.displayName, "—")
    try t.expect(torrent.statusValue == .stopped, "stopped by default")
    try t.expectEqual(torrent.progress, 0)
}

await t.test("FileStat priority decoding") {
    let json = #"{"bytesCompleted":100,"wanted":true,"priority":1}"#.data(using: .utf8)!
    let stat = try JSONDecoder().decode(TorrentFileStat.self, from: json)
    try t.expect(stat.wanted, "wanted")
    try t.expect(stat.priorityValue == .high, "high priority")
}

await t.test("SessionInfo kebab-case fields") {
    let json = #"{"version":"4.0.5","rpc-version":17,"download-dir":"/downloads","speed-limit-down":500,"alt-speed-enabled":true}"#.data(using: .utf8)!
    let info = try JSONDecoder().decode(SessionInfo.self, from: json)
    try t.expectEqual(info.version, "4.0.5")
    try t.expectEqual(info.rpcVersion, 17)
    try t.expectEqual(info.downloadDir, "/downloads")
    try t.expectEqual(info.speedLimitDown, 500)
    try t.expectEqual(info.altSpeedEnabled, true)
}

print("\nSort keys")

await t.test("sizeSortKey prefers sizeWhenDone, then falls back to totalSize") {
    var a = Torrent(id: 1); a.sizeWhenDone = 500; a.totalSize = 900
    try t.expectEqual(a.sizeSortKey, 500)
    var b = Torrent(id: 2); b.totalSize = 700
    try t.expectEqual(b.sizeSortKey, 700)
    try t.expectEqual(Torrent(id: 3).sizeSortKey, 0)
}

await t.test("etaSortKey sorts unknown ETA to the end") {
    var known = Torrent(id: 1); known.eta = 120
    try t.expectEqual(known.etaSortKey, 120)
    var unknown = Torrent(id: 2); unknown.eta = -1
    try t.expectEqual(unknown.etaSortKey, Int.max)
    try t.expectEqual(Torrent(id: 3).etaSortKey, Int.max) // missing field
}

await t.test("Sorting by addedDateSortKey puts the newest first (reverse)") {
    var old = Torrent(id: 1); old.addedDate = 1_000
    var new = Torrent(id: 2); new.addedDate = 2_000
    let sorted = [old, new].sorted(using: [KeyPathComparator(\Torrent.addedDateSortKey, order: .reverse)])
    try t.expectEqual(sorted.map(\.id), [2, 1])
}

print("\nTorrentSort (fast sorting)")

func mkTorrent(_ id: Int, name: String, size: Int? = nil, added: Int? = nil, eta: Int? = nil) -> Torrent {
    var t = Torrent(id: id); t.name = name; t.sizeWhenDone = size; t.addedDate = added; t.eta = eta; return t
}

await t.test("Natural (Finder-like) sorting by name: file2 < file10") {
    let items = [mkTorrent(1, name: "file10"), mkTorrent(2, name: "file2"), mkTorrent(3, name: "file1")]
    let sorted = TorrentSort.apply(items, [KeyPathComparator(\.displayName, order: .forward)])
    try t.expectEqual(sorted.map(\.id), [3, 2, 1]) // file1, file2, file10
}

await t.test("Descending by size") {
    let items = [mkTorrent(1, name: "a", size: 100), mkTorrent(2, name: "b", size: 900), mkTorrent(3, name: "c", size: 500)]
    let sorted = TorrentSort.apply(items, [KeyPathComparator(\.sizeSortKey, order: .reverse)])
    try t.expectEqual(sorted.map(\.id), [2, 3, 1])
}

await t.test("Added date descending (newest first)") {
    let items = [mkTorrent(1, name: "a", added: 1000), mkTorrent(2, name: "b", added: 3000), mkTorrent(3, name: "c", added: 2000)]
    let sorted = TorrentSort.apply(items, [KeyPathComparator(\.addedDateSortKey, order: .reverse)])
    try t.expectEqual(sorted.map(\.id), [2, 3, 1])
}

await t.test("Last activity descending — never active goes to the end") {
    var a = mkTorrent(1, name: "a"); a.activityDate = 1000
    var b = mkTorrent(2, name: "b"); b.activityDate = 0
    var c = mkTorrent(3, name: "c"); c.activityDate = 3000
    let sorted = TorrentSort.apply([a, b, c], [KeyPathComparator(\.activityDateSortKey, order: .reverse)])
    try t.expectEqual(sorted.map(\.id), [3, 1, 2])
    try t.expect(b.activityDateValue == nil, "activityDate 0 should display as never")
}

await t.test("Ascending by ETA — unknown goes to the end") {
    let items = [mkTorrent(1, name: "a", eta: 500), mkTorrent(2, name: "b", eta: -1), mkTorrent(3, name: "c", eta: 100)]
    let sorted = TorrentSort.apply(items, [KeyPathComparator(\.etaSortKey, order: .forward)])
    try t.expectEqual(sorted.map(\.id), [3, 1, 2]) // 100, 500, unknown
}

await t.test("Order is unchanged with empty sort") {
    let items = [mkTorrent(3, name: "c"), mkTorrent(1, name: "a")]
    try t.expectEqual(TorrentSort.apply(items, []).map(\.id), [3, 1])
}

print("\nServerConfig URL")

await t.test("Plain host + HTTPS toggle produces the correct URL") {
    let c = ServerConfig(host: "torrent.example.com", port: 443, useHTTPS: true)
    try t.expectEqual(c.url?.absoluteString, "https://torrent.example.com:443/transmission/rpc")
}

await t.test("Strips a https:// prefix typed into the host field") {
    let c = ServerConfig(host: "https://torrent.example.com", port: 443, useHTTPS: true)
    try t.expectEqual(c.url?.absoluteString, "https://torrent.example.com:443/transmission/rpc")
}

await t.test("An explicit scheme in the host overrides the toggle") {
    // useHTTPS=false, but the host has https:// → the result should be https
    let c = ServerConfig(host: "https://torrent.example.com", port: 443, useHTTPS: false)
    try t.expectEqual(c.url?.scheme, "https")
}

await t.test("Trims a path that strayed into the host field") {
    let c = ServerConfig(host: "torrent.example.com/transmission/rpc", port: 443, useHTTPS: true)
    try t.expectEqual(c.url?.host, "torrent.example.com")
    try t.expectEqual(c.url?.absoluteString, "https://torrent.example.com:443/transmission/rpc")
}

print("\nSession settings")

await t.test("An empty SessionSetArgs sends no fields at all") {
    let data = try JSONEncoder().encode(SessionSetArgs())
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    try t.expect(json.isEmpty, "empty args → empty JSON object")
}

await t.test("SessionSetArgs sends only the set fields, with the correct kebab-case key") {
    var args = SessionSetArgs()
    args.peerLimitGlobal = 300
    args.dhtEnabled = false
    let data = try JSONEncoder().encode(args)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    try t.expectEqual(json.count, 2)
    try t.expectEqual(json["peer-limit-global"] as? Int, 300)
    try t.expectEqual(json["dht-enabled"] as? Bool, false)
}

await t.test("SessionSetArgs sends the seed-ratio fields in camelCase") {
    var args = SessionSetArgs()
    args.seedRatioLimit = 2.5
    args.seedRatioLimited = true
    let data = try JSONEncoder().encode(args)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    try t.expectEqual(json["seedRatioLimit"] as? Double, 2.5)
    try t.expectEqual(json["seedRatioLimited"] as? Bool, true)
    try t.expect(json["seed-ratio-limit"] == nil, "must not go out in kebab-case")
}

await t.test("SessionInfo decodes the new session-get fields") {
    let jsonStr = #"{"peer-limit-global":240,"peer-limit-per-torrent":60,"dht-enabled":true,"pex-enabled":false,"seedRatioLimit":1.75,"seedRatioLimited":true,"incomplete-dir":"/tmp/inc","download-queue-size":7,"encryption":"required"}"#
    let info = try JSONDecoder().decode(SessionInfo.self, from: Data(jsonStr.utf8))
    try t.expectEqual(info.peerLimitGlobal, 240)
    try t.expectEqual(info.peerLimitPerTorrent, 60)
    try t.expectEqual(info.dhtEnabled, true)
    try t.expectEqual(info.pexEnabled, false)
    try t.expectEqual(info.seedRatioLimit, 1.75)
    try t.expectEqual(info.seedRatioLimited, true)
    try t.expectEqual(info.incompleteDir, "/tmp/inc")
    try t.expectEqual(info.downloadQueueSize, 7)
    try t.expect(info.encryptionValue == .required, "encryption enum conversion")
}

print("\nRSS parsing")

await t.test("RSSParser extracts RSS 2.0 items (magnet link + enclosure fallback + guid)") {
    let xml = #"""
    <?xml version="1.0"?>
    <rss version="2.0"><channel><title>Feed</title>
    <item><title>Movie.2025.1080p</title><link>magnet:?xt=urn:btih:abc</link><guid>g1</guid></item>
    <item><title>Show.S01E01</title><enclosure url="https://x/t.torrent"/><guid>g2</guid></item>
    </channel></rss>
    """#
    let items = RSSParser.parse(Data(xml.utf8))
    try t.expectEqual(items.count, 2)
    try t.expectEqual(items[0].title, "Movie.2025.1080p")
    try t.expectEqual(items[0].link, "magnet:?xt=urn:btih:abc")
    try t.expectEqual(items[0].guid, "g1")
    try t.expectEqual(items[1].link, "https://x/t.torrent")   // enclosure URL used when <link> is absent
}

await t.test("RSSParser handles Atom entries (link href + id)") {
    let xml = #"""
    <?xml version="1.0"?>
    <feed><entry><title>Atom.Item</title><link href="magnet:?xt=urn:btih:xyz"/><id>a1</id></entry></feed>
    """#
    let items = RSSParser.parse(Data(xml.utf8))
    try t.expectEqual(items.count, 1)
    try t.expectEqual(items[0].link, "magnet:?xt=urn:btih:xyz")
    try t.expectEqual(items[0].guid, "a1")
}

print("\ntorrent-set-location")

await t.test("torrentSetLocation sends the new location and asks the daemon to move the data") {
    MockURLProtocol.reset()
    MockURLProtocol.handler = { _, _ in (200, [:], #"{"result":"success","arguments":{},"tag":0}"#.data(using: .utf8)!) }
    try await makeClient().torrentSetLocation(ids: .ids([.id(7), .id(9)]), location: "/mnt/data/movies", move: true)
    let body = try t.unwrap(MockURLProtocol.lastBodies.last)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    try t.expectEqual(json["method"] as? String, "torrent-set-location")
    let args = try t.unwrap(json["arguments"] as? [String: Any])
    try t.expectEqual(args["ids"] as? [Int], [7, 9])
    try t.expectEqual(args["location"] as? String, "/mnt/data/movies")
    try t.expectEqual(args["move"] as? Bool, true)
}

await t.test("torrentSetLocation can register a new location without moving the files") {
    MockURLProtocol.reset()
    MockURLProtocol.handler = { _, _ in (200, [:], #"{"result":"success","arguments":{},"tag":0}"#.data(using: .utf8)!) }
    try await makeClient().torrentSetLocation(ids: .ids([.id(1)]), location: "/tank/done", move: false)
    let body = try t.unwrap(MockURLProtocol.lastBodies.last)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let args = try t.unwrap(json["arguments"] as? [String: Any])
    try t.expectEqual(args["move"] as? Bool, false)
}

await t.test("torrentSetLocation refuses .all and an empty id list without sending anything") {
    // An omitted ids key means "every torrent" to the daemon — relocating a whole
    // library must never be reachable by accident.
    for ids in [RPCIds.all, .recentlyActive, .ids([])] {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _, _ in (200, [:], #"{"result":"success","arguments":{},"tag":0}"#.data(using: .utf8)!) }
        var threw = false
        do { try await makeClient().torrentSetLocation(ids: ids, location: "/tank", move: true) }
        catch is RPCError { threw = true }
        try t.expect(threw, "\(ids) must be rejected")
        try t.expectEqual(MockURLProtocol.requestCount, 0)
    }
}

await t.test("torrentSetLocation encodes hash identifiers as strings") {
    MockURLProtocol.reset()
    MockURLProtocol.handler = { _, _ in (200, [:], #"{"result":"success","arguments":{},"tag":0}"#.data(using: .utf8)!) }
    try await makeClient().torrentSetLocation(ids: .ids([.hash("abc123")]), location: "/tank", move: true)
    let body = try t.unwrap(MockURLProtocol.lastBodies.last)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let args = try t.unwrap(json["arguments"] as? [String: Any])
    try t.expectEqual(args["ids"] as? [String], ["abc123"])
}

await t.test("torrentSetLocation throws on a non-success result") {
    MockURLProtocol.reset()
    MockURLProtocol.handler = { _, _ in (200, [:], #"{"result":"no such directory","arguments":{},"tag":0}"#.data(using: .utf8)!) }
    var threw = false
    do { try await makeClient().torrentSetLocation(ids: .ids([.id(1)]), location: "/nope", move: true) }
    catch is RPCError { threw = true }
    try t.expect(threw, "it should have thrown an RPCError")
}

print("\ntorrent-rename-path")

await t.test("torrentRenamePath sends a single id with the old path and the new name") {
    MockURLProtocol.reset()
    MockURLProtocol.handler = { _, _ in (200, [:], #"{"result":"success","arguments":{"id":3,"path":"Old","name":"New"},"tag":0}"#.data(using: .utf8)!) }
    try await makeClient().torrentRenamePath(id: 3, path: "Old", name: "New")
    let body = try t.unwrap(MockURLProtocol.lastBodies.last)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    try t.expectEqual(json["method"] as? String, "torrent-rename-path")
    let args = try t.unwrap(json["arguments"] as? [String: Any])
    try t.expectEqual(args["ids"] as? [Int], [3])
    try t.expectEqual(args["path"] as? String, "Old")
    try t.expectEqual(args["name"] as? String, "New")
    try t.expect(args["id"] == nil, "the classic daemon wants an ids array, not a singular id")
}

await t.test("torrentRenamePath throws on a non-success result") {
    MockURLProtocol.reset()
    MockURLProtocol.handler = { _, _ in (200, [:], #"{"result":"invalid argument","arguments":{},"tag":0}"#.data(using: .utf8)!) }
    var threw = false
    do { try await makeClient().torrentRenamePath(id: 1, path: "A", name: "B") }
    catch is RPCError { threw = true }
    try t.expect(threw, "it should have thrown an RPCError")
}

print("\nContext menu rules")

await t.test("targetRows keeps the whole selection when the click lands inside it") {
    let selection = IndexSet([1, 2, 5])
    try t.expectEqual(TorrentRowMenu.targetRows(clicked: 2, selection: selection), selection)
}

await t.test("targetRows targets only the clicked row when it is outside the selection") {
    try t.expectEqual(TorrentRowMenu.targetRows(clicked: 7, selection: IndexSet([1, 2])), IndexSet(integer: 7))
}

await t.test("targetRows targets the clicked row when nothing is selected") {
    try t.expectEqual(TorrentRowMenu.targetRows(clicked: 0, selection: IndexSet()), IndexSet(integer: 0))
}

await t.test("targetRows targets nothing when the click misses every row") {
    try t.expect(TorrentRowMenu.targetRows(clicked: -1, selection: IndexSet([1])).isEmpty,
                 "no menu on empty space")
}

await t.test("Every command is disabled without a target") {
    for command in TorrentRowCommand.allCases {
        try t.expect(!TorrentRowMenu.isEnabled(command, for: []), "\(command) must be disabled")
    }
}

await t.test("Start is offered for stopped torrents, Stop for running ones") {
    var stopped = Torrent(id: 1); stopped.status = Torrent.Status.stopped.rawValue
    var running = Torrent(id: 2); running.status = Torrent.Status.downloading.rawValue
    try t.expect(TorrentRowMenu.isEnabled(.start, for: [stopped]), "stopped -> start")
    try t.expect(!TorrentRowMenu.isEnabled(.stop, for: [stopped]), "stopped -> no stop")
    try t.expect(TorrentRowMenu.isEnabled(.stop, for: [running]), "running -> stop")
    try t.expect(!TorrentRowMenu.isEnabled(.start, for: [running]), "running -> no start")
    try t.expect(TorrentRowMenu.isEnabled(.start, for: [stopped, running]), "mixed -> start")
    try t.expect(TorrentRowMenu.isEnabled(.stop, for: [stopped, running]), "mixed -> stop")
}

await t.test("Rename is limited to a single named torrent") {
    var a = Torrent(id: 1); a.name = "A"
    var b = Torrent(id: 2); b.name = "B"
    let unnamed = Torrent(id: 3)
    try t.expect(TorrentRowMenu.isEnabled(.rename, for: [a]), "one torrent -> rename")
    try t.expect(!TorrentRowMenu.isEnabled(.rename, for: [a, b]), "torrent-rename-path takes a single id")
    try t.expect(!TorrentRowMenu.isEnabled(.rename, for: [unnamed]), "without a name there is no path to rename")
}

await t.test("Copying needs the underlying field, the remaining commands only need a target") {
    var withHash = Torrent(id: 1); withHash.name = "A"; withHash.hashString = "abc"
    var noHash = Torrent(id: 2); noHash.name = "B"
    let bare = Torrent(id: 3)
    try t.expect(TorrentRowMenu.isEnabled(.copyHash, for: [withHash]), "hash present -> enabled")
    try t.expect(!TorrentRowMenu.isEnabled(.copyHash, for: [noHash]), "no hash -> disabled")
    try t.expect(!TorrentRowMenu.isEnabled(.copyName, for: [bare]), "no name -> disabled")
    for command in [TorrentRowCommand.move, .removeKeepData, .removeWithData] {
        try t.expect(TorrentRowMenu.isEnabled(command, for: [bare]), "\(command) only needs a target")
    }
}

await t.test("sanitizedName trims, rejects empty names and path separators") {
    try t.expectEqual(TorrentRowMenu.sanitizedName("  Ubuntu 24.04  "), "Ubuntu 24.04")
    try t.expect(TorrentRowMenu.sanitizedName("   ") == nil, "an empty name is invalid")
    try t.expect(TorrentRowMenu.sanitizedName("a/b") == nil, "a rename cannot contain a path separator")
}

await t.test("sanitizedLocation trims and rejects an empty path") {
    try t.expectEqual(TorrentRowMenu.sanitizedLocation(" /mnt/data "), "/mnt/data")
    try t.expect(TorrentRowMenu.sanitizedLocation("   ") == nil, "an empty location is invalid")
}

print("\nContext menu layout")

await t.test("Every command appears in the menu layout exactly once") {
    let listed = TorrentRowMenu.layout.map(\.command)
    try t.expectEqual(Set(listed), Set(TorrentRowCommand.allCases))
    try t.expectEqual(listed.count, TorrentRowCommand.allCases.count)
}

await t.test("The layout does not end with a separator") {
    let last = try t.unwrap(TorrentRowMenu.layout.last)
    try t.expect(!last.separatorAfter, "a trailing separator draws an empty strip at the menu's bottom")
}

await t.test("Every layout entry has a title key") {
    for entry in TorrentRowMenu.layout {
        try t.expect(!entry.titleKey.isEmpty, "\(entry.command) has no title")
    }
}

print("\nRow to torrent mapping")

await t.test("targets maps row indices to torrents in row order") {
    let torrents = [Torrent(id: 10), Torrent(id: 11), Torrent(id: 12)]
    let picked = TorrentRowMenu.targets(rows: IndexSet([0, 2]), in: torrents)
    try t.expectEqual(picked.map(\.id), [10, 12])
}

await t.test("targets drops rows the current snapshot no longer has") {
    // The list is refreshed by polling, so a captured row index can outlive its data.
    let torrents = [Torrent(id: 10), Torrent(id: 11)]
    let picked = TorrentRowMenu.targets(rows: IndexSet([1, 40]), in: torrents)
    try t.expectEqual(picked.map(\.id), [11])
}

await t.test("targets returns nothing when every row is gone") {
    try t.expect(TorrentRowMenu.targets(rows: IndexSet([5, 6]), in: [Torrent(id: 1)]).isEmpty,
                 "a fully stale selection must produce no command targets")
}

print("\nCommand enablement — states")

await t.test("Queued torrents count as running for Start/Stop") {
    var queuedDown = Torrent(id: 1); queuedDown.status = Torrent.Status.queuedToDownload.rawValue
    var queuedSeed = Torrent(id: 2); queuedSeed.status = Torrent.Status.queuedToSeed.rawValue
    for torrent in [queuedDown, queuedSeed] {
        try t.expect(TorrentRowMenu.isEnabled(.stop, for: [torrent]), "queued -> stoppable")
        try t.expect(!TorrentRowMenu.isEnabled(.start, for: [torrent]), "queued -> already started")
    }
}

await t.test("Verify is disabled while the torrent is already being checked") {
    var verifying = Torrent(id: 1); verifying.status = Torrent.Status.verifying.rawValue
    var queued = Torrent(id: 2); queued.status = Torrent.Status.queuedToVerify.rawValue
    var stopped = Torrent(id: 3); stopped.status = Torrent.Status.stopped.rawValue
    try t.expect(!TorrentRowMenu.isEnabled(.verify, for: [verifying]), "already verifying")
    try t.expect(!TorrentRowMenu.isEnabled(.verify, for: [queued]), "already queued to verify")
    try t.expect(TorrentRowMenu.isEnabled(.verify, for: [stopped]), "stopped -> verifiable")
    try t.expect(TorrentRowMenu.isEnabled(.verify, for: [verifying, stopped]), "mixed -> offer it")
}

await t.test("Reannounce needs at least one running torrent") {
    var stopped = Torrent(id: 1); stopped.status = Torrent.Status.stopped.rawValue
    var seeding = Torrent(id: 2); seeding.status = Torrent.Status.seeding.rawValue
    try t.expect(!TorrentRowMenu.isEnabled(.reannounce, for: [stopped]), "stopped -> no announce to refresh")
    try t.expect(TorrentRowMenu.isEnabled(.reannounce, for: [seeding]), "seeding -> reannounce")
    try t.expect(TorrentRowMenu.isEnabled(.reannounce, for: [stopped, seeding]), "mixed -> offer it")
}

await t.test("An empty name blocks Rename and Copy name just like a missing one") {
    var blank = Torrent(id: 1); blank.name = ""
    try t.expect(!TorrentRowMenu.isEnabled(.rename, for: [blank]), "empty name -> nothing to rename")
    try t.expect(!TorrentRowMenu.isEnabled(.copyName, for: [blank]), "empty name -> nothing to copy")
}

await t.test("An empty hash blocks Copy hash") {
    var blank = Torrent(id: 1); blank.hashString = ""
    try t.expect(!TorrentRowMenu.isEnabled(.copyHash, for: [blank]), "empty hash -> nothing to copy")
}

print("\nInput validation")

await t.test("sanitizedName rejects path separators and traversal shapes") {
    for bad in ["", "   ", "a/b", "a/b/c", "/abs", "a\\b", ".", "..", " .. "] {
        try t.expect(TorrentRowMenu.sanitizedName(bad) == nil, "\(bad.debugDescription) must be rejected")
    }
}

await t.test("sanitizedName rejects the unchanged name") {
    try t.expect(TorrentRowMenu.sanitizedName("Ubuntu", current: "Ubuntu") == nil,
                 "renaming to the same value is a wasted round trip")
    try t.expect(TorrentRowMenu.sanitizedName("  Ubuntu  ", current: "Ubuntu") == nil,
                 "whitespace alone is not a change")
    try t.expectEqual(TorrentRowMenu.sanitizedName("Ubuntu 2", current: "Ubuntu"), "Ubuntu 2")
}

await t.test("sanitizedName keeps accented and non-ASCII names") {
    try t.expectEqual(TorrentRowMenu.sanitizedName("Árvíztűrő tükörfúrógép"), "Árvíztűrő tükörfúrógép")
    try t.expectEqual(TorrentRowMenu.sanitizedName(" 日本語 🎬 "), "日本語 🎬")
}

await t.test("sanitizedLocation rejects relative and tilde paths") {
    for bad in ["", "   ", "backups", "./backups", "../up", "~/Downloads", "~"] {
        try t.expect(TorrentRowMenu.sanitizedLocation(bad) == nil, "\(bad.debugDescription) must be rejected")
    }
}

await t.test("sanitizedLocation accepts POSIX and Windows absolute paths") {
    try t.expectEqual(TorrentRowMenu.sanitizedLocation(" /mnt/data "), "/mnt/data")
    try t.expectEqual(TorrentRowMenu.sanitizedLocation("/mnt/data/"), "/mnt/data/")
    // The client is macOS-only, the daemon is not.
    try t.expectEqual(TorrentRowMenu.sanitizedLocation("C:\\Downloads"), "C:\\Downloads")
    try t.expectEqual(TorrentRowMenu.sanitizedLocation("D:/media"), "D:/media")
}

print("\nIncoming torrents (Open With / magnet)")

await t.test("A .torrent file URL is a file, any other file is rejected") {
    try t.expect(IncomingTorrent.classify(URL(fileURLWithPath: "/tmp/Ubuntu.TORRENT")) == .file(URL(fileURLWithPath: "/tmp/Ubuntu.TORRENT")), ".torrent should be a file")
    try t.expect(IncomingTorrent.classify(URL(fileURLWithPath: "/tmp/notes.txt")) == nil, ".txt must be rejected")
}

await t.test("Magnet and http(s) URLs are links, other schemes are rejected") {
    let magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=x"
    try t.expect(IncomingTorrent.classify(URL(string: magnet)!) == .link(magnet), "magnet should be a link")
    try t.expect(IncomingTorrent.classify(URL(string: "https://example.com/a.torrent")!) == .link("https://example.com/a.torrent"), "https should be a link")
    try t.expect(IncomingTorrent.classify(URL(string: "ftp://example.com/a.torrent")!) == nil, "ftp must be rejected")
}

await t.test("Dragged text: trimmed magnet is accepted, plain text is not") {
    try t.expect(IncomingTorrent.classify(text: "  magnet:?xt=urn:btih:abc\n") == .link("magnet:?xt=urn:btih:abc"), "trimmed magnet")
    try t.expect(IncomingTorrent.classify(text: "hello world") == nil, "plain text must be rejected")
}

await t.test("Queue keeps order, drops duplicates and drains exactly once") {
    var q = IncomingQueue()
    q.enqueue([.link("magnet:?a"), .link("magnet:?b")])
    q.enqueue([.link("magnet:?a"), .file(URL(fileURLWithPath: "/tmp/x.torrent"))])
    try t.expectEqual(q.drain(), [.link("magnet:?a"), .link("magnet:?b"), .file(URL(fileURLWithPath: "/tmp/x.torrent"))])
    try t.expectEqual(q.drain(), [])
}

print("\nTracker + rule-mezők dekódolása")

await t.test("Tracker matchHost a sitename-et használja, ha a daemon adja (4.0+)") {
    let json = #"{"id":0,"announce":"http://tracker.example.org:6969/announce","sitename":"example","tier":0}"#
    let tr = try JSONDecoder().decode(Tracker.self, from: Data(json.utf8))
    try t.expectEqual(tr.matchHost, "example")
}

await t.test("Tracker matchHost az announce hostjából származtat, ha nincs sitename (3.x)") {
    let json = #"{"id":0,"announce":"http://tracker.example.org:6969/announce","tier":0}"#
    let tr = try JSONDecoder().decode(Tracker.self, from: Data(json.utf8))
    try t.expectEqual(tr.matchHost, "tracker.example.org")
}

await t.test("Tracker matchHost nil, ha az announce értelmezhetetlen") {
    let tr = try JSONDecoder().decode(Tracker.self, from: Data(#"{"announce":"nem-url"}"#.utf8))
    try t.expect(tr.matchHost == nil, "hosztolhatatlan announce -> nil")
}

await t.test("Torrent dekódolja a trackers tömböt és a seed-limit mezőket") {
    let json = #"{"id":1,"trackers":[{"announce":"http://a.org/announce"}],"seedRatioLimit":2.5,"seedRatioMode":1,"seedIdleLimit":30,"seedIdleMode":1}"#
    let tor = try JSONDecoder().decode(Torrent.self, from: Data(json.utf8))
    try t.expectEqual(tor.trackers?.count, 1)
    try t.expectEqual(tor.seedRatioLimit, 2.5)
    try t.expectEqual(tor.seedRatioMode, 1)
    try t.expectEqual(tor.seedIdleLimit, 30)
    try t.expectEqual(tor.seedIdleMode, 1)
}

await t.test("torrent-set kiküldi a seed ratio/idle párokat a helyes kulcsokkal") {
    MockURLProtocol.reset()
    MockURLProtocol.handler = { _, _ in (200, [:], #"{"result":"success","arguments":{},"tag":0}"#.data(using: .utf8)!) }
    var args = TorrentSetArgs(ids: .ids([.id(1)]))
    args.seedRatioLimit = 2.5
    args.seedRatioMode = 1
    args.seedIdleLimit = 30
    args.seedIdleMode = 1
    try await makeClient().torrentSet(args)
    let body = try t.unwrap(MockURLProtocol.lastBodies.last)
    let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let a = try t.unwrap(json["arguments"] as? [String: Any])
    try t.expectEqual(a["seedRatioLimit"] as? Double, 2.5)
    try t.expectEqual(a["seedRatioMode"] as? Int, 1)
    try t.expectEqual(a["seedIdleLimit"] as? Int, 30)
    try t.expectEqual(a["seedIdleMode"] as? Int, 1)
}

await t.test("ruleInputs tartalmaz minden mezőt, amit az összehasonlításhoz olvasunk") {
    for field in ["id", "hashString", "name", "status", "labels", "trackers",
                  "seedRatioLimit", "seedRatioMode", "seedIdleLimit", "seedIdleMode",
                  "uploadLimit", "uploadLimited", "downloadLimit", "downloadLimited"] {
        try t.expect(TorrentFields.ruleInputs.contains(field), "\(field) hiányzik a ruleInputs-ból")
    }
}

print("\nSzabály-feltételek illesztése")

await t.test("textMatches: részszöveg, kis/nagybetű-független") {
    try t.expect(RuleMatcher.textMatches("Ubuntu 24.04 LTS", pattern: "ubuntu"), "részszöveg")
    try t.expect(!RuleMatcher.textMatches("Ubuntu", pattern: "debian"), "nem illeszkedő")
}

await t.test("textMatches: /regex/ alak") {
    try t.expect(RuleMatcher.textMatches("Show.S01E05.1080p", pattern: "/S\\d+E\\d+/"), "regex")
    try t.expect(!RuleMatcher.textMatches("Film.2024", pattern: "/S\\d+E\\d+/"), "nem illeszkedő regex")
}

await t.test("textMatches: hibás regex nem omlik össze, csak nem illeszkedik") {
    try t.expect(!RuleMatcher.textMatches("bármi", pattern: "/[/"), "hibás regex -> false")
}

await t.test("textMatches: üres minta soha nem illeszkedik") {
    try t.expect(!RuleMatcher.textMatches("bármi", pattern: "   "), "üres minta -> false")
}

await t.test("trackerHost részszövegre illeszt, hogy az x.org fogja a tracker.x.org-ot is") {
    let tor = Torrent(id: 1)
    try t.expect(RuleMatcher.matches(.trackerHost("x.org"), torrent: tor, trackerHosts: ["tracker.x.org"]), "részszöveg")
    try t.expect(RuleMatcher.matches(.trackerHost("X.ORG"), torrent: tor, trackerHosts: ["tracker.x.org"]), "kis/nagybetű")
    try t.expect(!RuleMatcher.matches(.trackerHost("y.org"), torrent: tor, trackerHosts: ["tracker.x.org"]), "más tracker")
}

await t.test("trackerHost illeszkedik, ha a torrent BÁRMELYIK trackere stimmel") {
    let tor = Torrent(id: 1)
    try t.expect(RuleMatcher.matches(.trackerHost("b.org"), torrent: tor, trackerHosts: ["a.org", "b.org"]), "több tracker")
}

await t.test("label pontos egyezés, nem részszöveg") {
    var tor = Torrent(id: 1); tor.labels = ["film"]
    try t.expect(RuleMatcher.matches(.label("film"), torrent: tor, trackerHosts: []), "pontos")
    try t.expect(RuleMatcher.matches(.label("FILM"), torrent: tor, trackerHosts: []), "kis/nagybetű-független")
    try t.expect(!RuleMatcher.matches(.label("fil"), torrent: tor, trackerHosts: []), "részszöveg NEM illeszthet")
}

await t.test("namePattern a torrent nevére illeszt, név nélkül nem illeszkedik") {
    var tor = Torrent(id: 1); tor.name = "Ubuntu 24.04"
    try t.expect(RuleMatcher.matches(.namePattern("ubuntu"), torrent: tor, trackerHosts: []), "név")
    try t.expect(!RuleMatcher.matches(.namePattern("ubuntu"), torrent: Torrent(id: 2), trackerHosts: []), "nincs név")
}

await t.test("RuleActions.isEmpty igaz, ha semmit nem állít be") {
    try t.expect(RuleActions().isEmpty, "üres akció")
    var a = RuleActions(); a.seedRatio = 2.0
    try t.expect(!a.isEmpty, "van beállítás")
}

print("\nSzabálymotor — tervezés")

func ruleFixture(_ name: String, _ condition: RuleCondition, _ actions: RuleActions,
                 enabled: Bool = true) -> TorrentRule {
    TorrentRule(name: name, enabled: enabled, condition: condition, actions: actions)
}

await t.test("Az első illeszkedő szabály nyer, a többit nem nézzük") {
    var tor = Torrent(id: 1); tor.hashString = "h1"; tor.name = "A"; tor.labels = []
    let r1 = ruleFixture("első", .trackerHost("x.org"), RuleActions(seedRatio: 2.0))
    let r2 = ruleFixture("második", .trackerHost("x.org"), RuleActions(seedRatio: 9.0))
    let plan = RuleEngine.plan(rules: [r1, r2], torrents: [tor],
                               trackerHosts: [1: ["tracker.x.org"]], alreadyClassified: [])
    try t.expectEqual(plan.count, 1)
    try t.expectEqual(plan[0].ruleName, "első")
    try t.expectEqual(plan[0].effect.seedRatio, 2.0)
}

await t.test("A letiltott szabályt átugorja") {
    var tor = Torrent(id: 1); tor.hashString = "h1"
    let off = ruleFixture("ki", .trackerHost("x.org"), RuleActions(seedRatio: 2.0), enabled: false)
    let on = ruleFixture("be", .trackerHost("x.org"), RuleActions(seedRatio: 3.0))
    let plan = RuleEngine.plan(rules: [off, on], torrents: [tor],
                               trackerHosts: [1: ["x.org"]], alreadyClassified: [])
    try t.expectEqual(plan[0].ruleName, "be")
}

await t.test("A már besorolt torrentet kihagyja, force esetén nem") {
    var tor = Torrent(id: 1); tor.hashString = "h1"
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(seedRatio: 2.0))
    let skipped = RuleEngine.plan(rules: [r], torrents: [tor],
                                  trackerHosts: [1: ["x.org"]], alreadyClassified: ["h1"])
    try t.expect(skipped.isEmpty, "besorolt -> kihagyva")
    let forced = RuleEngine.plan(rules: [r], torrents: [tor],
                                 trackerHosts: [1: ["x.org"]], alreadyClassified: ["h1"], force: true)
    try t.expectEqual(forced.count, 1)
}

await t.test("A már beállított értéket nem küldi ki újra") {
    var tor = Torrent(id: 1); tor.hashString = "h1"
    tor.seedRatioLimit = 2.0; tor.seedRatioMode = 1
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(seedRatio: 2.0))
    let plan = RuleEngine.plan(rules: [r], torrents: [tor],
                               trackerHosts: [1: ["x.org"]], alreadyClassified: [])
    try t.expect(plan.isEmpty, "nincs változás -> a torrent ki sem kerül a tervbe")
}

await t.test("Ugyanaz a limit, de GLOBAL módban, változásnak számít") {
    var tor = Torrent(id: 1); tor.hashString = "h1"
    tor.seedRatioLimit = 2.0; tor.seedRatioMode = 0   // a limit ott van, de a daemon nem használja
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(seedRatio: 2.0))
    let plan = RuleEngine.plan(rules: [r], torrents: [tor],
                               trackerHosts: [1: ["x.org"]], alreadyClassified: [])
    try t.expectEqual(plan.count, 1)
}

await t.test("A seedRatio MINDIG a mode=1 párral megy ki") {
    var tor = Torrent(id: 1); tor.hashString = "h1"
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(seedRatio: 2.0, seedIdleMinutes: 30))
    let plan = RuleEngine.plan(rules: [r], torrents: [tor],
                               trackerHosts: [1: ["x.org"]], alreadyClassified: [])
    let args = RuleEngine.arguments(for: plan[0])
    try t.expectEqual(args.seedRatioLimit, 2.0)
    try t.expectEqual(args.seedRatioMode, 1)
    try t.expectEqual(args.seedIdleLimit, 30)
    try t.expectEqual(args.seedIdleMode, 1)
}

await t.test("A sebességkorlát a Limited kapcsolóval együtt megy ki") {
    var tor = Torrent(id: 1); tor.hashString = "h1"
    let r = ruleFixture("r", .trackerHost("x.org"),
                        RuleActions(uploadLimitKBps: 100, downloadLimitKBps: 200))
    let plan = RuleEngine.plan(rules: [r], torrents: [tor],
                               trackerHosts: [1: ["x.org"]], alreadyClassified: [])
    let args = RuleEngine.arguments(for: plan[0])
    try t.expectEqual(args.uploadLimit, 100)
    try t.expectEqual(args.uploadLimited, true)
    try t.expectEqual(args.downloadLimit, 200)
    try t.expectEqual(args.downloadLimited, true)
}

await t.test("Az addLabels hozzáad, nem helyettesít, és nem duplikál") {
    var tor = Torrent(id: 1); tor.hashString = "h1"; tor.labels = ["meglévő"]
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(addLabels: ["új", "meglévő"]))
    let plan = RuleEngine.plan(rules: [r], torrents: [tor],
                               trackerHosts: [1: ["x.org"]], alreadyClassified: [])
    let args = RuleEngine.arguments(for: plan[0])
    try t.expectEqual(args.labels, ["meglévő", "új"])
}

await t.test("Ha minden kért címke megvan, nincs változás") {
    var tor = Torrent(id: 1); tor.hashString = "h1"; tor.labels = ["a", "b"]
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(addLabels: ["a"]))
    let plan = RuleEngine.plan(rules: [r], torrents: [tor],
                               trackerHosts: [1: ["x.org"]], alreadyClassified: [])
    try t.expect(plan.isEmpty, "nincs új címke -> nincs terv")
}

await t.test("A stop csak futó torrenten számít változásnak") {
    var running = Torrent(id: 1); running.hashString = "h1"
    running.status = Torrent.Status.seeding.rawValue
    var stopped = Torrent(id: 2); stopped.hashString = "h2"
    stopped.status = Torrent.Status.stopped.rawValue
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(stop: true))
    let plan = RuleEngine.plan(rules: [r], torrents: [running, stopped],
                               trackerHosts: [1: ["x.org"], 2: ["x.org"]], alreadyClassified: [])
    try t.expectEqual(plan.count, 1)
    try t.expectEqual(plan[0].torrentID, 1)
    try t.expect(plan[0].alsoStop, "a futót le kell állítani")
}

await t.test("A terv mezőnként megmondja a régi és az új értéket") {
    var tor = Torrent(id: 1); tor.hashString = "h1"; tor.name = "A"
    tor.seedRatioLimit = 1.0; tor.seedRatioMode = 1
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(seedRatio: 2.0))
    let plan = RuleEngine.plan(rules: [r], torrents: [tor],
                               trackerHosts: [1: ["x.org"]], alreadyClassified: [])
    let change = try t.unwrap(plan[0].changes.first { $0.field == .seedRatio })
    try t.expectEqual(change.before, "1.0")
    try t.expectEqual(change.after, "2.0")
}

await t.test("Üres szabálylista vagy üres torrentlista -> üres terv") {
    var tor = Torrent(id: 1); tor.hashString = "h1"
    try t.expect(RuleEngine.plan(rules: [], torrents: [tor], trackerHosts: [:],
                                 alreadyClassified: []).isEmpty, "nincs szabály")
    let r = ruleFixture("r", .trackerHost("x.org"), RuleActions(seedRatio: 2.0))
    try t.expect(RuleEngine.plan(rules: [r], torrents: [], trackerHosts: [:],
                                 alreadyClassified: []).isEmpty, "nincs torrent")
}

exit(Int32(t.summary()))
