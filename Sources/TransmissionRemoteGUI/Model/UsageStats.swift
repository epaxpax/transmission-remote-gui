import Foundation
import Observation
import TransmissionKit

/// Opt-in, anonymous usage statistics: at most one GoatCounter request a day, carrying only
/// the app version, the macOS major version and the daemon's major.minor version (see
/// `UsagePing`). Off by default, and never asked for in a pop-up: the user switches it on
/// in Settings → General.
@MainActor @Observable
final class UsageStats {
    static let shared = UsageStats()

    static let enabledKey = "usageStatsEnabled"
    private static let lastPingKey = "usageStatsLastPing"
    /// Hidden override for the UI tests: a local server instead of GoatCounter.
    private static let endpointOverrideKey = "usagePingURL"

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    /// Called by the maintenance tick while connected; failures are silent (next tick retries).
    func pingIfDue(daemonVersion: String?) async {
        let last = UserDefaults.standard.object(forKey: Self.lastPingKey) as? Date
        guard isEnabled, let appVersion = UpdateChecker.currentVersion,
              UsagePing.isDue(lastPing: last, now: Date()) else { return }
        let endpoint = UserDefaults.standard.string(forKey: Self.endpointOverrideKey).flatMap(URL.init(string:))
            ?? UsagePing.endpoint
        let path = UsagePing.path(appVersion: appVersion,
                                  macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                                  daemonVersion: daemonVersion)
        var request = URLRequest(url: UsagePing.url(endpoint: endpoint, path: path), timeoutInterval: 20)
        request.setValue("TransmissionRemoteGUI/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("*", forHTTPHeaderField: "Accept-Language")   // not the system locale
        // Ephemeral: no cookies or cache, so nothing ties one day's ping to the next.
        guard let (_, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false
        else { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastPingKey)
    }
}
