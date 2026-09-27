import Foundation

/// The part of GitHub's "latest release" response the update check reads. The
/// `/releases/latest` endpoint already skips drafts and pre-releases.
public struct ReleaseInfo: Decodable, Equatable, Sendable {
    public let tagName: String
    public let htmlURL: URL

    public init(tagName: String, htmlURL: URL) {
        self.tagName = tagName; self.htmlURL = htmlURL
    }

    /// "v0.1.9" → "0.1.9".
    public var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

public enum AppVersion {
    /// Numeric, component-wise comparison ("0.1.10" is newer than "0.1.9"); a missing
    /// component counts as 0 and anything after a "-" (a pre-release suffix) is ignored.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        return core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}

/// When to check for a new release, and whether to offer it.
public enum UpdateCheck {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/epaxpax/transmission-remote-gui/releases/latest")!
    public static let interval: TimeInterval = 24 * 3600

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// A newer release the user has not chosen to skip.
    public static func shouldOffer(_ release: ReleaseInfo, current: String, skipped: String?) -> Bool {
        AppVersion.isNewer(release.version, than: current) && release.version != skipped
    }
}

/// The opt-in, anonymous daily usage ping (GoatCounter). It carries ONLY the app version,
/// the macOS major version and the daemon's major.minor version — encoded in the counted
/// path — and no identifier of any kind.
public enum UsagePing {
    public static let endpoint = URL(string: "https://trgui.goatcounter.com/count")!

    /// "/app/0.1.9/macos-15/tr-4.1" (or "tr-none" before any daemon was seen).
    public static func path(appVersion: String, macOSMajor: Int, daemonVersion: String?) -> String {
        "/app/\(safe(appVersion))/macos-\(macOSMajor)/tr-\(daemonVersion.flatMap(majorMinor) ?? "none")"
    }

    /// The GoatCounter count request: the path, plus a random value against HTTP caches
    /// (the same thing GoatCounter's own count.js sends).
    public static func url(endpoint: URL = endpoint, path: String) -> URL {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "p", value: path),
                        URLQueryItem(name: "rnd", value: String(Int.random(in: 100_000...999_999)))]
        return c.url!
    }

    /// At most one ping per calendar day.
    public static func isDue(lastPing: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastPing else { return true }
        return !calendar.isDate(lastPing, inSameDayAs: now)
    }

    /// "4.1.3 (a1b2c3)" → "4.1"; nil when the string holds no version number.
    static func majorMinor(_ daemonVersion: String) -> String? {
        let numbers = daemonVersion.split(separator: " ").first.map(String.init) ?? daemonVersion
        let parts = numbers.split(separator: ".").prefix(2).map { $0.filter(\.isNumber) }
        guard let major = parts.first, !major.isEmpty else { return nil }
        return parts.count > 1 && !parts[1].isEmpty ? "\(major).\(parts[1])" : major
    }

    /// Keeps a version usable as one path segment (digits, dots, letters, dashes only).
    private static func safe(_ s: String) -> String {
        let kept = s.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return kept.isEmpty ? "unknown" : kept
    }
}
