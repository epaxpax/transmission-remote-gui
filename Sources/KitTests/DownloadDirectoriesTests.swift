import Foundation
import TransmissionKit

func testDownloadDirectories(_ t: TestHarness) async {
    print("\nAdd dialog download directories")

    await t.test("History: most recent first, deduplicated, trailing slash and whitespace ignored") {
        var dirs = DownloadDirectories()
        dirs.recordUsed("/srv/a")
        dirs.recordUsed(" /srv/b/ ")
        dirs.recordUsed("/srv/a/")
        try t.expectEqual(dirs.recent, ["/srv/a", "/srv/b"])
    }
    await t.test("History: capped at the limit, oldest dropped") {
        var dirs = DownloadDirectories()
        for i in 1...(DownloadDirectories.recentLimit + 3) { dirs.recordUsed("/srv/\(i)") }
        try t.expectEqual(dirs.recent.count, DownloadDirectories.recentLimit)
        try t.expectEqual(dirs.recent.first, "/srv/\(DownloadDirectories.recentLimit + 3)")
        try t.expectEqual(dirs.recent.last, "/srv/4")
    }
    await t.test("History: empty input is ignored, clear empties it") {
        var dirs = DownloadDirectories(recent: ["/srv/x"])
        dirs.recordUsed("   ")
        try t.expectEqual(dirs.recent, ["/srv/x"])
        dirs.clearRecent()
        try t.expect(dirs.recent.isEmpty, "history cleared")
    }
    await t.test("Favorites: add keeps order and skips duplicates, remove matches normalized") {
        var dirs = DownloadDirectories()
        dirs.addFavorite("/srv/电影")
        dirs.addFavorite("/srv/b")
        dirs.addFavorite("/srv/电影/")
        try t.expectEqual(dirs.favorites, ["/srv/电影", "/srv/b"])
        try t.expect(dirs.isFavorite(" /srv/b/"), "normalized lookup")
        dirs.removeFavorite("/srv/电影/")
        try t.expectEqual(dirs.favorites, ["/srv/b"])
        dirs.addFavorite("")
        try t.expectEqual(dirs.favorites, ["/srv/b"])
    }
    await t.test("Normalization keeps roots and Windows drive roots") {
        try t.expectEqual(DownloadDirectories.normalized("/"), "/")
        try t.expectEqual(DownloadDirectories.normalized("C:\\"), "C:\\")
        try t.expectEqual(DownloadDirectories.normalized("C:\\Downloads\\"), "C:\\Downloads")
        try t.expectEqual(DownloadDirectories.normalized("/srv//"), "/srv")
        try t.expectEqual(DownloadDirectories.normalized(" \n"), nil)
    }
    await t.test("Effective download-dir: omitted when empty or equal to the daemon default") {
        try t.expectEqual(DownloadDirectories.effectiveDownloadDir("", daemonDefault: "/srv/dl"), nil)
        try t.expectEqual(DownloadDirectories.effectiveDownloadDir(" /srv/dl/ ", daemonDefault: "/srv/dl"), nil)
        try t.expectEqual(DownloadDirectories.effectiveDownloadDir("/srv/other", daemonDefault: "/srv/dl"), "/srv/other")
        try t.expectEqual(DownloadDirectories.effectiveDownloadDir("/srv/other", daemonDefault: nil), "/srv/other")
    }
    await t.test("Codable round trip; decoding normalizes, dedupes and caps") {
        var dirs = DownloadDirectories()
        dirs.addFavorite("/srv/fav")
        dirs.recordUsed("/srv/recent")
        let decoded = try JSONDecoder().decode(DownloadDirectories.self, from: try JSONEncoder().encode(dirs))
        try t.expectEqual(decoded, dirs)
        let many = (1...20).map { "\"/srv/\($0)/\"" }.joined(separator: ",")
        let json = #"{"favorites":["/a/","/a"],"recent":[\#(many)]}"#
        let messy = try JSONDecoder().decode(DownloadDirectories.self, from: Data(json.utf8))
        try t.expectEqual(messy.favorites, ["/a"])
        try t.expectEqual(messy.recent.count, DownloadDirectories.recentLimit)
        try t.expectEqual(messy.recent.first, "/srv/1")
        let empty = try JSONDecoder().decode(DownloadDirectories.self, from: Data("{}".utf8))
        try t.expect(empty.isEmpty, "missing keys decode as empty")
    }
}
