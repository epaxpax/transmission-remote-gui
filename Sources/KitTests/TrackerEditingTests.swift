import Foundation
import TransmissionKit

func testTrackerEditing(_ t: TestHarness) async {
    print("\nTracker editing")
    await t.test("Tracker list version gate is independent of label support") {
        for version in [nil, 0, 15, 16] as [Int?] {
            try t.expect(!TrackerListSupport.isSupported(rpcVersion: version), "legacy setter")
        }
        for version in [17, 18, 99] {
            try t.expect(TrackerListSupport.isSupported(rpcVersion: version), "trackerList setter")
        }
        try t.expectEqual(TrackerListSupport.minimumRPCVersion, 17)
        try t.expect(TorrentLabelSupport.isSupported(rpcVersion: 16), "labels have a different minimum")
    }
    await t.test("Tracker input accepts only supported schemes with a host") {
        for value in ["http://a.invalid/announce", "https://a.invalid/path?passkey=example",
                      "udp://a.invalid:6969/announce", "HTTP://a.invalid/announce", "http://[::1]:8080/a"] {
            try t.expectEqual(TrackerEdit.validatedURL(" \n" + value + "\t"), value)
        }
        for value in ["", "   ", "a.invalid", "http://", "file:///tmp/a", "ftp://a.invalid/a",
                      "magnet:?xt=a", "https://a.invalid/a b", "http://a.invalid/a\nhttp://b.invalid/a"] {
            try t.expectEqual(TrackerEdit.validatedURL(value), nil)
        }
    }
    let existing = [Tracker(id: 4, announce: "https://a.invalid/a?key=example", tier: 5),
                    Tracker(id: 8, announce: "udp://b.invalid:80/a", tier: 5),
                    Tracker(id: 9, announce: "https://c.invalid/a", tier: 2)]
    let encoded = "https://c.invalid/a\n\nhttps://a.invalid/a?key=example\nudp://b.invalid:80/a"
    await t.test("Tracker serialization preserves tier and URL order without exposing gaps") {
        try t.expectEqual(try TrackerEdit.trackerList(existing), encoded)
        try t.expectEqual(try TrackerEdit.trackerList([]), "")
    }
    await t.test("Incomplete tracker metadata cannot erase or inject tiers") {
        for entry in [Tracker(tier: 0), Tracker(announce: "http://a.invalid/a"),
                      Tracker(announce: "http://a.invalid/a\n\nhttp://b.invalid/a", tier: 0)] {
            var threw = false
            do { _ = try TrackerEdit.trackerList([entry]) }
            catch TrackerEditError.incompleteTrackers { threw = true }
            try t.expect(threw, "reject incomplete list")
        }
    }
    for version in [16, 17, 18] {
        for removing in [false, true] {
            await t.test("RPC \(version) \(removing ? "remove" : "add") reads fresh metadata before a single-target write") {
                MockURLProtocol.reset()
                let fixture = try JSONEncoder().encode(existing)
                MockURLProtocol.handler = { _, count in
                    let response = count == 1
                        ? "{\"result\":\"success\",\"arguments\":{\"torrents\":[{\"id\":7,\"trackers\":\(String(decoding: fixture, as: UTF8.self))}]}}"
                        : #"{"result":"success","arguments":{}}"#
                    return (200, [:], Data(response.utf8))
                }
                let edit: TrackerEdit = removing ? .remove("https://a.invalid/a?key=example") : .add(" https://new.invalid/a ")
                try await makeClient().editTracker(edit, torrentID: 7, rpcVersion: version)
                try t.expectEqual(MockURLProtocol.requestCount, 2)
                let requests = try MockURLProtocol.lastBodies.map { data in
                    try t.unwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                }
                try t.expectEqual(requests[0]["method"] as? String, "torrent-get")
                let read = try t.unwrap(requests[0]["arguments"] as? [String: Any])
                try t.expectEqual(read["ids"] as? [Int], [7])
                try t.expectEqual(read["fields"] as? [String], ["id", "trackers"])
                try t.expectEqual(requests[1]["method"] as? String, "torrent-set")
                let write = try t.unwrap(requests[1]["arguments"] as? [String: Any])
                try t.expectEqual(write["ids"] as? [Int], [7])
                if version >= 17 {
                    let expected = removing ? "https://c.invalid/a\n\nudp://b.invalid:80/a" : encoded + "\n\nhttps://new.invalid/a"
                    try t.expectEqual(write["trackerList"] as? String, expected)
                    try t.expectEqual(Set(write.keys), Set(["ids", "trackerList"]))
                } else if removing {
                    try t.expectEqual(write["trackerRemove"] as? [Int], [4])
                    try t.expectEqual(Set(write.keys), Set(["ids", "trackerRemove"]))
                } else {
                    try t.expectEqual(write["trackerAdd"] as? [String], ["https://new.invalid/a"])
                    try t.expectEqual(Set(write.keys), Set(["ids", "trackerAdd"]))
                }
            }
        }
        for edit in [TrackerEdit.add("https://a.invalid/a"), .remove("http://missing.invalid/a")] {
            await t.test("RPC \(version) repeated add/remove is idempotent") {
                MockURLProtocol.reset()
                MockURLProtocol.handler = { _, _ in
                    (200, [:], Data(#"{"result":"success","arguments":{"torrents":[{"id":7,"trackers":[{"id":99,"tier":0,"announce":"https://a.invalid/a"}]}]}}"#.utf8))
                }
                try await makeClient().editTracker(edit, torrentID: 7, rpcVersion: version)
                try t.expectEqual(MockURLProtocol.requestCount, 1)
            }
        }
    }
    for version in [16, 17] {
        await t.test("RPC \(version) last tracker removal encodes a real empty list or tracker ID") {
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _, count in
                (200, [:], Data((count == 1
                    ? #"{"result":"success","arguments":{"torrents":[{"id":7,"trackers":[{"id":12,"tier":0,"announce":"https://a.invalid/a"}]}]}}"#
                    : #"{"result":"success","arguments":{}}"#).utf8))
            }
            try await makeClient().editTracker(.remove("https://a.invalid/a"), torrentID: 7, rpcVersion: version)
            let request = try t.unwrap(try JSONSerialization.jsonObject(with: MockURLProtocol.lastBodies[1]) as? [String: Any])
            let args = try t.unwrap(request["arguments"] as? [String: Any])
            if version == 17 { try t.expectEqual(args["trackerList"] as? String, "") }
            else { try t.expectEqual(args["trackerRemove"] as? [Int], [12]) }
        }
    }
    await t.test("Invalid add makes no network request") {
        MockURLProtocol.reset()
        do {
            try await makeClient().editTracker(.add("file:///tmp/a"), torrentID: 7, rpcVersion: 17)
            throw TestFailure(message: "invalid URL accepted")
        } catch TrackerEditError.invalidURL {}
        try t.expectEqual(MockURLProtocol.requestCount, 0)
    }
    for body in [#"{"torrents":[]}"#, #"{"torrents":[{"id":8,"trackers":[]}]}"#,
                 #"{"torrents":[{"id":7}]}"#, #"{"torrents":[{"id":7,"trackers":[{"id":1,"tier":0}]}]}"#] {
        await t.test("Missing torrent or incomplete metadata prevents destructive list replacement") {
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _, _ in
                (200, [:], Data("{\"result\":\"success\",\"arguments\":\(body)}".utf8))
            }
            var threw = false
            do { try await makeClient().editTracker(.add("http://new.invalid/a"), torrentID: 7, rpcVersion: 17) }
            catch is TrackerEditError { threw = true }
            try t.expect(threw, "incomplete response rejected")
            try t.expectEqual(MockURLProtocol.requestCount, 1)
        }
    }
    for failureAt in [1, 2] {
        await t.test("Tracker read/write failure reaches the caller") {
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _, count in
                let text = count == failureAt ? #"{"result":"test rejection","arguments":{}}"#
                    : #"{"result":"success","arguments":{"torrents":[{"id":7,"trackers":[]}]}}"#
                return (200, [:], Data(text.utf8))
            }
            var threw = false
            do { try await makeClient().editTracker(.add("http://new.invalid/a"), torrentID: 7, rpcVersion: 17) }
            catch is RPCError { threw = true }
            try t.expect(threw, "daemon failure propagated")
            try t.expectEqual(MockURLProtocol.requestCount, failureAt)
        }
    }
    await t.test("Tracker edit retries session handshake and preserves exact target") {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _, count in
            if count == 1 { return (409, ["X-Transmission-Session-Id": "tracker-test"], Data()) }
            return (200, [:], Data((count == 2
                ? #"{"result":"success","arguments":{"torrents":[{"id":7,"trackers":[]}]}}"#
                : #"{"result":"success","arguments":{}}"#).utf8))
        }
        try await makeClient().editTracker(.add("http://new.invalid/a"), torrentID: 7, rpcVersion: 17)
        try t.expectEqual(MockURLProtocol.requestCount, 3)
        try t.expectEqual(MockURLProtocol.lastBodies[0], MockURLProtocol.lastBodies[1])
    }
}
