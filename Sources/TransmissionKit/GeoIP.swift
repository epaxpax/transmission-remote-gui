import Foundation

/// IP → country lookup for the Peers tab's flags. The table is built from DB-IP's
/// "IP to Country Lite" data by `Scripts/geoip.py` (format described there) and ships
/// inside the app, so no peer address ever leaves the machine.
public struct GeoIPTable: Sendable {
    private let codes: [String]
    private let starts4: [UInt32], index4: [UInt8]
    private let starts6: [UInt64], index6: [UInt8]

    public var rangeCount: Int { starts4.count + starts6.count }

    /// `compressed` is the raw-deflate file the script writes; nil if it is not one.
    public init?(compressed: Data) {
        guard let raw = try? (compressed as NSData).decompressed(using: .zlib) as Data else { return nil }
        self.init(raw: raw)
    }

    init?(raw: Data) {
        var r = Reader(bytes: [UInt8](raw))
        guard r.take(6) == Array("TRGEO1".utf8), let nc = r.int(2), let cc = r.take(nc * 2) else { return nil }
        codes = stride(from: 0, to: cc.count, by: 2).map { String(decoding: cc[$0..<$0 + 2], as: UTF8.self) }
        guard let n4 = r.int(4), let s4 = r.take(n4 * 4), let i4 = r.take(n4),
              let n6 = r.int(4), let s6 = r.take(n6 * 8), let i6 = r.take(n6), r.atEnd else { return nil }
        starts4 = Reader.uints(s4, width: 4).map(UInt32.init)
        starts6 = Reader.uints(s6, width: 8)
        index4 = i4
        index6 = i6
    }

    /// ISO country code ("HU") of an IPv4 / IPv6 address; nil for private, reserved or
    /// unknown addresses and anything that is not an IP.
    public func country(for address: String) -> String? {
        guard let ip = IPAddress(address) else { return nil }
        let idx: UInt8?
        if let v4 = ip.v4 {
            idx = Self.lookup(starts4, index4, v4)
        } else {
            idx = Self.lookup(starts6, index6, ip.high64)
        }
        guard let idx, Int(idx) < codes.count else { return nil }
        return codes[Int(idx)]
    }

    /// The last range starting at or below `key` (ranges run until the next start).
    private static func lookup<T: Comparable>(_ starts: [T], _ index: [UInt8], _ key: T) -> UInt8? {
        var lo = 0, hi = starts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if starts[mid] <= key { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : index[lo - 1]
    }

    private struct Reader {
        let bytes: [UInt8]
        var pos = 0
        var atEnd: Bool { pos == bytes.count }

        mutating func take(_ n: Int) -> [UInt8]? {
            guard n >= 0, pos + n <= bytes.count else { return nil }
            defer { pos += n }
            return Array(bytes[pos..<pos + n])
        }
        mutating func int(_ width: Int) -> Int? {
            take(width).map { $0.reduce(0) { $0 << 8 | Int($1) } }
        }
        static func uints(_ b: [UInt8], width: Int) -> [UInt64] {
            stride(from: 0, to: b.count, by: width).map { o in
                b[o..<o + width].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            }
        }
    }
}

/// A parsed IPv4 or IPv6 address (IPv4-mapped IPv6 counts as IPv4).
public struct IPAddress: Sendable {
    /// The 16 bytes of the IPv6 form (IPv4 as `::ffff:a.b.c.d`).
    public let bytes: [UInt8]

    public init?(_ string: String) {
        let s = string.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, s, &v4) == 1 {
            bytes = [UInt8](repeating: 0, count: 10) + [0xFF, 0xFF] + withUnsafeBytes(of: v4) { Array($0) }
        } else if inet_pton(AF_INET6, s, &v6) == 1 {
            bytes = withUnsafeBytes(of: v6) { Array($0) }
        } else {
            return nil
        }
    }

    public var v4: UInt32? {
        guard bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF else { return nil }
        return bytes[12...].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    var high64: UInt64 { bytes[0..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) } }

}

/// Numeric address order (9.x before 84.x, IPv4 before IPv6, non-IP text last). A type of
/// its own: SwiftUI's `KeyPathComparator` compares strings Finder-style, which would read
/// digit runs in a text key as numbers.
public struct AddressSortKey: Comparable, Hashable, Sendable {
    let bytes: [UInt8]?
    let text: String

    public init(_ address: String) {
        bytes = IPAddress(address)?.bytes
        text = address
    }

    public static func < (a: Self, b: Self) -> Bool {
        switch (a.bytes, b.bytes) {
        case let (x?, y?): return x.lexicographicallyPrecedes(y)
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.text < b.text
        }
    }
}

public enum CountryFlag {
    /// "HU" → 🇭🇺 (regional indicator symbols; macOS draws them as flags).
    public static func emoji(_ code: String) -> String? {
        let letters = code.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        return String(String.UnicodeScalarView(letters.compactMap { UnicodeScalar(0x1F1A5 + $0.value) }))
    }
}

extension Peer {
    /// Numeric address order for the Peers table; non-IP text sorts last.
    public var addressSortKey: AddressSortKey { AddressSortKey(address) }
    public var clientSortKey: String { clientName ?? "" }
}

extension TrackerStat {
    public var seederSortKey: Int { seederCount ?? -1 }
    public var leecherSortKey: Int { leecherCount ?? -1 }
    public var resultSortKey: String { lastAnnounceResult ?? "" }
}
