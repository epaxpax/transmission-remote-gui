import Foundation
import TransmissionKit

func testQueue(_ t: TestHarness) async {
    print("\nDownload queue")
    let moves: [(QueueMove, String)] = [
        (.top, "queue-move-top"), (.up, "queue-move-up"),
        (.down, "queue-move-down"), (.bottom, "queue-move-bottom"),
    ]
    for (move, method) in moves {
        await t.test("\(method) sends one request with all selected IDs") {
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _, _ in
                (200, [:], Data(#"{"result":"success","arguments":{}}"#.utf8))
            }
            // Deliberately not in ID or queue order: do not reorder or split the selection.
            try await makeClient().queueMove(move, ids: .ids([.id(9), .id(2), .id(7)]))
            try t.expectEqual(MockURLProtocol.requestCount, 1)
            let body = try t.unwrap(MockURLProtocol.lastBodies.last)
            let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            try t.expectEqual(json["method"] as? String, method)
            let args = try t.unwrap(json["arguments"] as? [String: Any])
            try t.expectEqual(args["ids"] as? [Int], [9, 2, 7])
            try t.expectEqual(Set(args.keys), Set(["ids"]))
        }
        await t.test("\(method) never sends an empty selection") {
            MockURLProtocol.reset()
            try await makeClient().queueMove(move, ids: .ids([]))
            try t.expectEqual(MockURLProtocol.requestCount, 0)
        }
        await t.test("\(method) propagates daemon errors") {
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _, _ in
                (200, [:], Data(#"{"result":"invalid argument","arguments":{}}"#.utf8))
            }
            var threw = false
            do { try await makeClient().queueMove(move, ids: .ids([.id(3)])) }
            catch is RPCError { threw = true }
            try t.expect(threw, "daemon errors must reach the action error UI")
        }
    }
    await t.test("Queue move retries the 409 handshake with the same selected IDs") {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _, count in
            if count == 1 { return (409, ["X-Transmission-Session-Id": "queue-test"], Data()) }
            return (200, [:], Data(#"{"result":"success","arguments":{}}"#.utf8))
        }
        try await makeClient().queueMove(.top, ids: .ids([.id(8), .id(4)]))
        try t.expectEqual(MockURLProtocol.requestCount, 2)
        for body in MockURLProtocol.lastBodies {
            let json = try t.unwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let args = try t.unwrap(json["arguments"] as? [String: Any])
            try t.expectEqual(args["ids"] as? [Int], [8, 4])
        }
    }
    await t.test("List polling requests and decodes zero-based queue positions") {
        try t.expect(TorrentFields.list.contains("queuePosition"), "polling must refresh queue positions")
        let item = try JSONDecoder().decode(Torrent.self, from: Data(#"{"id":7,"queuePosition":0}"#.utf8))
        try t.expectEqual(item.queuePosition, 0)
        try t.expectEqual(item.queuePositionText, "1")
        var tenth = Torrent(id: 10); tenth.queuePosition = 9
        try t.expectEqual(tenth.queuePositionText, "10")
    }
    await t.test("Unknown and invalid queue positions do not display a fabricated position") {
        for position in [nil, -1, Int.max] as [Int?] {
            var item = Torrent(id: 1); item.queuePosition = position
            try t.expectEqual(item.queuePositionText, "—")
        }
        let missing = try JSONDecoder().decode(Torrent.self, from: Data(#"{"id":1}"#.utf8))
        try t.expectEqual(missing.queuePosition, nil)
    }
    await t.test("Queue positions sort numerically in both directions, independently of names") {
        let items = [9, 1, 0, 10, 2].enumerated().map { id, position in
            var item = Torrent(id: id); item.queuePosition = position; item.name = "same"
            return item
        }
        for order in [SortOrder.forward, .reverse] {
            let comparator = KeyPathComparator(\Torrent.queuePositionSortKey, order: order)
            let sorted = TorrentSort.apply(items, [comparator])
            try t.expectEqual(sorted.compactMap(\.queuePosition),
                              order == .forward ? [0, 1, 2, 9, 10] : [10, 9, 2, 1, 0])
            try t.expectEqual(sorted.map(\.id), items.sorted(using: comparator).map(\.id))
        }
        try t.expectEqual(items.compactMap(\.queuePosition), [9, 1, 0, 10, 2])
    }
    let commands: [TorrentRowCommand] = [.queueTop, .queueUp, .queueDown, .queueBottom]
    await t.test("Queue commands form a separate flat group in the row menu") {
        let layout = TorrentRowMenu.layout
        let first = try t.unwrap(layout.firstIndex { $0.command == .queueTop })
        try t.expect(first > 0 && layout[first - 1].separatorAfter, "separator before queue group")
        try t.expectEqual(Array(layout[first..<(first + 4)]).map(\.command), commands)
        try t.expectEqual(Array(layout[first..<(first + 4)]).map(\.separatorAfter),
                          [false, false, false, true])
    }
    await t.test("Queue actions need a selection, regardless of torrent status") {
        for command in commands {
            try t.expect(!TorrentRowMenu.isEnabled(command, for: []), "empty selection disabled")
            for status in 0...6 {
                var torrent = Torrent(id: 3); torrent.status = status
                try t.expect(TorrentRowMenu.isEnabled(command, for: [torrent]), "selected torrent enabled")
            }
            try t.expect(TorrentRowMenu.isEnabled(command, for: [Torrent(id: 3), Torrent(id: 8)]),
                         "multi-selection enabled")
        }
    }
}
