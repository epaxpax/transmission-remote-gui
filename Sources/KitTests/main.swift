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

exit(Int32(t.summary()))
