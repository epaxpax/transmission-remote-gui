import Foundation
import TransmissionKit

func testTorrentProperties(_ t: TestHarness) async {
    print("\nBatch torrent properties")

    func props(_ id: Int, labels: [String]? = nil, down: Int? = nil, peer: Int? = nil) -> TorrentProperties {
        var p = TorrentProperties(id: id)
        p.labels = labels
        p.downloadLimit = down
        p.peerLimit = peer
        return p
    }
    func json(_ args: TorrentSetArgs) throws -> [String: Any] {
        let data = try JSONEncoder().encode(args)
        return try t.unwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func ids(_ args: TorrentSetArgs) throws -> [Int] {
        try t.unwrap(try json(args)["ids"] as? [Int])
    }

    // MARK: Mixed values

    await t.test("Mixed value: all equal -> uniform, differing -> mixed, none -> unknown") {
        try t.expectEqual(MixedValue([props(1, down: 50), props(2, down: 50)], \.downloadLimit), .uniform(50))
        try t.expectEqual(MixedValue([props(1, down: 50), props(2, down: 80)], \.downloadLimit), .mixed)
        try t.expectEqual(MixedValue([props(1), props(2)], \.downloadLimit), .unknown)
        try t.expectEqual(MixedValue([TorrentProperties](), \.downloadLimit), .unknown)
    }

    await t.test("Mixed value: a torrent missing the field makes it mixed, not uniform") {
        try t.expectEqual(MixedValue([props(1, down: 50), props(2)], \.downloadLimit), .mixed)
        try t.expectEqual(MixedValue([props(1), props(2, down: 50)], \.downloadLimit), .mixed)
        try t.expectEqual(MixedValue([props(1, down: 7)], \.downloadLimit).uniformValue, 7)
    }

    // MARK: Unchanged fields

    await t.test("No edits -> nothing to send") {
        let edits = TorrentPropertyEdits()
        try t.expect(edits.isEmpty, "a fresh edit set is empty")
        try t.expect(edits.setArgs(for: [props(1), props(2)]).isEmpty, "no torrent-set call")
    }

    await t.test("An empty add/remove is no edit at all") {
        var edits = TorrentPropertyEdits()
        edits.labels = .modify(add: [], remove: [])
        try t.expect(edits.isEmpty, "empty modify is a no-op")
        try t.expect(edits.setArgs(for: [props(1, labels: ["a"])]).isEmpty, "no call")
    }

    await t.test("Only edited fields are encoded, in one call for every id") {
        var edits = TorrentPropertyEdits()
        edits.uploadLimited = true
        edits.uploadLimit = 250
        edits.bandwidthPriority = .high
        let calls = edits.setArgs(for: [props(1), props(2), props(3)])
        try t.expectEqual(calls.count, 1)
        let body = try json(calls[0])
        try t.expectEqual(Set(body.keys), ["ids", "uploadLimited", "uploadLimit", "bandwidthPriority"])
        try t.expectEqual(try ids(calls[0]), [1, 2, 3])
        try t.expectEqual(body["bandwidthPriority"] as? Int, 1)
        try t.expectEqual(body["uploadLimit"] as? Int, 250)
    }

    await t.test("Peer limit and session-limit flag use the daemon's key names") {
        var edits = TorrentPropertyEdits()
        edits.peerLimit = 80
        edits.honorsSessionLimits = false
        edits.downloadLimited = false
        let body = try json(try t.unwrap(edits.setArgs(for: [props(4)]).first))
        try t.expectEqual(body["peer-limit"] as? Int, 80)
        try t.expectEqual(body["honorsSessionLimits"] as? Bool, false)
        try t.expectEqual(body["downloadLimited"] as? Bool, false)
        try t.expect(body["peerLimit"] == nil, "camelCase peerLimit is not an RPC key")
        try t.expect(body["labels"] == nil, "labels untouched")
    }

    // MARK: Labels

    await t.test("Label parsing trims, drops empties and case-insensitive duplicates") {
        try t.expectEqual(TorrentLabels.parse(" movies, ,TV,  movies ,Movies,"), ["movies", "TV"])
        try t.expectEqual(TorrentLabels.parse("   "), [])
    }

    await t.test("Adding labels keeps every existing label") {
        try t.expectEqual(TorrentLabels.apply(.modify(add: ["new"], remove: []), to: ["a", "b"]), ["a", "b", "new"])
        try t.expectEqual(TorrentLabels.apply(.modify(add: ["A"], remove: []), to: ["a"]), ["a"])
    }

    await t.test("Removing labels touches only those labels, case-insensitively") {
        try t.expectEqual(TorrentLabels.apply(.modify(add: [], remove: ["movies"]), to: ["Movies", "4k"]), ["4k"])
        try t.expectEqual(TorrentLabels.apply(.modify(add: [], remove: ["absent"]), to: ["x"]), ["x"])
    }

    await t.test("A label both added and removed ends up removed") {
        try t.expectEqual(TorrentLabels.apply(.modify(add: ["x", "y"], remove: ["x"]), to: ["a"]), ["a", "y"])
    }

    await t.test("Replace overwrites the whole list") {
        try t.expectEqual(TorrentLabels.apply(.replace(["z", "Z", "y"]), to: ["a", "b"]), ["z", "y"])
        try t.expectEqual(TorrentLabels.apply(.replace([]), to: ["a"]), [])
    }

    await t.test("Common and partial labels across the selection") {
        let lists = [["a", "b", "c"], ["B", "a"], ["a", "b", "d"]]
        try t.expectEqual(TorrentLabels.common(lists), ["a", "b"])
        try t.expectEqual(TorrentLabels.partial(lists), ["c", "d"])
        try t.expectEqual(TorrentLabels.common([]), [])
    }

    await t.test("Add label: per-torrent lists, grouped by result, unchanged torrents skipped") {
        var edits = TorrentPropertyEdits()
        edits.labels = .modify(add: ["hd"], remove: [])
        let torrents = [props(1, labels: ["movie"]), props(2, labels: ["tv"]), props(3, labels: ["movie"]),
                        props(4, labels: ["movie", "hd"])]
        let calls = edits.setArgs(for: torrents)
        try t.expectEqual(calls.count, 2)
        try t.expectEqual(try ids(calls[0]), [1, 3])
        try t.expectEqual(calls[0].labels, ["movie", "hd"])
        try t.expectEqual(try ids(calls[1]), [2])
        try t.expectEqual(calls[1].labels, ["tv", "hd"])
    }

    await t.test("Remove label never clears the other labels of a mixed selection") {
        var edits = TorrentPropertyEdits()
        edits.labels = .modify(add: [], remove: ["old"])
        let calls = edits.setArgs(for: [props(1, labels: ["old", "keep1"]), props(2, labels: ["keep2"]),
                                       props(3, labels: nil)])
        try t.expectEqual(calls.count, 1)
        try t.expectEqual(try ids(calls[0]), [1])
        try t.expectEqual(calls[0].labels, ["keep1"])
    }

    await t.test("Same resulting labels for all: one call carrying labels and the other edits") {
        var edits = TorrentPropertyEdits()
        edits.peerLimit = 40
        edits.labels = .replace(["x"])
        let calls = edits.setArgs(for: [props(1, labels: ["a"]), props(2, labels: [])])
        try t.expectEqual(calls.count, 1)
        try t.expectEqual(try ids(calls[0]), [1, 2])
        try t.expectEqual(calls[0].labels, ["x"])
        try t.expectEqual(calls[0].peerLimit, 40)
    }

    await t.test("Differing label results: field call for all ids, label calls per group") {
        var edits = TorrentPropertyEdits()
        edits.downloadLimit = 100
        edits.labels = .modify(add: ["n"], remove: [])
        let calls = edits.setArgs(for: [props(1, labels: ["a"]), props(2, labels: ["b"]), props(3, labels: ["n"])])
        try t.expectEqual(calls.count, 3)
        try t.expectEqual(try ids(calls[0]), [1, 2, 3])
        try t.expectEqual(calls[0].downloadLimit, 100)
        try t.expect(calls[0].labels == nil, "the shared call must not carry a single label list")
        try t.expectEqual(calls[1].labels, ["a", "n"])
        try t.expectEqual(calls[2].labels, ["b", "n"])
        try t.expect(calls[1].downloadLimit == nil, "label calls carry labels only")
    }

    await t.test("A label edit that changes nothing sends nothing") {
        var edits = TorrentPropertyEdits()
        edits.labels = .modify(add: ["a"], remove: [])
        try t.expect(edits.setArgs(for: [props(1, labels: ["a"]), props(2, labels: ["A", "b"])]).isEmpty,
                     "every torrent already has the label")
    }

    // MARK: Validation, decoding, support

    await t.test("Speed and peer limits parse within the daemon's ranges") {
        try t.expectEqual(TorrentPropertyEdits.parseSpeedLimit(" 0 "), 0)
        try t.expectEqual(TorrentPropertyEdits.parseSpeedLimit("1500"), 1500)
        try t.expect(TorrentPropertyEdits.parseSpeedLimit("-1") == nil, "negative")
        try t.expect(TorrentPropertyEdits.parseSpeedLimit("1.5") == nil, "fraction")
        try t.expect(TorrentPropertyEdits.parseSpeedLimit("") == nil, "empty")
        try t.expect(TorrentPropertyEdits.parseSpeedLimit("99999999999") == nil, "beyond 32 bits")
        try t.expectEqual(TorrentPropertyEdits.parsePeerLimit("60"), 60)
        try t.expect(TorrentPropertyEdits.parsePeerLimit("0") == nil, "zero peers")
        try t.expect(TorrentPropertyEdits.parsePeerLimit("70000") == nil, "beyond 16 bits")
    }

    await t.test("Decodes the editor's torrent-get fields, including peer-limit") {
        let data = Data(#"""
        {"id": 9, "name": "x", "labels": ["a"], "downloadLimit": 10, "downloadLimited": true,
         "uploadLimit": 20, "uploadLimited": false, "honorsSessionLimits": true,
         "bandwidthPriority": -1, "peer-limit": 50}
        """#.utf8)
        let p = try JSONDecoder().decode(TorrentProperties.self, from: data)
        try t.expectEqual(p.peerLimit, 50)
        try t.expectEqual(p.bandwidthPriority, BandwidthPriority.low.rawValue)
        try t.expectEqual(p.honorsSessionLimits, true)
        try t.expectEqual(p.labels, ["a"])
        try t.expect(TorrentProperties.fields.contains("peer-limit"), "requested under the RPC name")
    }

    await t.test("Labels need RPC 16 (Transmission 3.00); unknown version is allowed") {
        try t.expect(!TorrentLabelSupport.isSupported(rpcVersion: 15), "2.9x has no labels")
        try t.expect(TorrentLabelSupport.isSupported(rpcVersion: 16), "3.00")
        try t.expect(TorrentLabelSupport.isSupported(rpcVersion: 17), "4.x")
        try t.expect(TorrentLabelSupport.isSupported(rpcVersion: nil), "unknown")
    }

    await t.test("Properties is a context-menu command for any selection") {
        try t.expect(TorrentRowMenu.isEnabled(.editProperties, for: [Torrent(id: 1), Torrent(id: 2)]), "multi")
        try t.expect(!TorrentRowMenu.isEnabled(.editProperties, for: []), "no target")
    }
}
