import AppKit
import Observation
import TransmissionKit

/// Opt-in, anonymous usage statistics: at most one GoatCounter request a day, carrying only
/// the app version, the macOS major version and the daemon's major.minor version (see
/// `UsagePing`). Off until the user says yes — asked once, after the first successful
/// connection — and switchable in Settings → General.
@MainActor @Observable
final class UsageStats {
    static let shared = UsageStats()

    /// nil = not asked yet.
    static let enabledKey = "usageStatsEnabled"
    private static let lastPingKey = "usageStatsLastPing"
    /// Hidden override for the UI tests: a local server instead of GoatCounter.
    private static let endpointOverrideKey = "usagePingURL"

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private var hasAnswered: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) != nil }

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    /// Asks once, the first time the app is connected (so the user has seen it work).
    func askConsentIfNeeded() {
        guard !hasAnswered, UpdateChecker.currentVersion != nil else { return }
        let alert = NSAlert()
        alert.messageText = loc("Segítesz névtelen használati statisztikával?")
        alert.informativeText = loc("Naponta legfeljebb egyszer elküldjük az app verzióját, a macOS főverzióját és a Transmission-daemon verzióját. Semmi mást: nincs azonosító, szervercím vagy torrent-adat. Bármikor kikapcsolható: Beállítások → Általános.")
        alert.addButton(withTitle: loc("Igen, küldhető"))
        alert.addButton(withTitle: loc("Nem"))
        NSApp.activate(ignoringOtherApps: true)
        isEnabled = alert.runModal() == .alertFirstButtonReturn
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
