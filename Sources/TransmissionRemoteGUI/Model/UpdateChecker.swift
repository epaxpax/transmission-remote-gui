import AppKit
import Observation
import TransmissionKit

/// Daily check for a newer GitHub release, plus the manual "Check for Updates…" menu item.
/// It only asks api.github.com for the latest release number, and can be switched off in
/// Settings → General. Nothing is downloaded or installed: the user is pointed to the
/// release page (or the `brew upgrade` command, for Homebrew installs).
///
/// Deliberately unobtrusive: an automatic check never pops anything up — a newer release
/// only shows as a small link in the sidebar. The alert opens when the user clicks it, or
/// for a manual check.
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let enabledKey = "updateCheckEnabled"
    private static let lastCheckKey = "updateLastCheck"
    private static let skippedKey = "updateSkippedVersion"
    /// The last release found (tag + page), so the sidebar link survives a relaunch
    /// instead of vanishing until the next daily check.
    private static let latestTagKey = "updateLatestTag"
    private static let latestURLKey = "updateLatestURL"
    /// Hidden override for the UI tests: a local server instead of GitHub.
    private static let feedOverrideKey = "updateFeedURL"

    static let brewCommand = "brew upgrade --cask epaxpax/tap/transmission-remote-gui-macos"

    /// Automatic daily check (default on).
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// A newer, not skipped release — shown as a link in the sidebar until dealt with.
    private(set) var available: ReleaseInfo?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        let d = UserDefaults.standard
        if isEnabled, let current = Self.currentVersion,
           let tag = d.string(forKey: Self.latestTagKey),
           let url = d.string(forKey: Self.latestURLKey).flatMap(URL.init(string:)) {
            let release = ReleaseInfo(tagName: tag, htmlURL: url)
            if UpdateCheck.shouldOffer(release, current: current, skipped: d.string(forKey: Self.skippedKey)) {
                available = release
            }
        }
    }

    /// The running app's version; nil outside an .app bundle (`swift run`), where checking is pointless.
    static var currentVersion: String? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Called by the app's maintenance tick: checks when a day has passed since the last check.
    func checkIfDue() async {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        guard isEnabled, UpdateCheck.isDue(lastCheck: last, now: Date()) else { return }
        await check(manual: false)
    }

    /// A manual check ignores a skipped version and always reports the result.
    func check(manual: Bool) async {
        guard let current = Self.currentVersion else { return }
        do {
            let release = try await fetchLatest(current: current)
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            UserDefaults.standard.set(release.tagName, forKey: Self.latestTagKey)
            UserDefaults.standard.set(release.htmlURL.absoluteString, forKey: Self.latestURLKey)
            let skipped = manual ? nil : UserDefaults.standard.string(forKey: Self.skippedKey)
            if UpdateCheck.shouldOffer(release, current: current, skipped: skipped) {
                available = release
                if manual { presentAvailable() }
            } else {
                available = nil
                if manual { inform(loc("A legfrissebb verziót használod") + " (\(current)).") }
            }
        } catch {
            // An automatic check fails silently (offline, rate limit…) and retries tomorrow.
            if manual { inform(loc("Nem sikerült a frissítések keresése"), detail: error.localizedDescription) }
        }
    }

    /// The "new version" alert — also opened from the sidebar button.
    func presentAvailable() {
        guard let release = available, let current = Self.currentVersion else { return }
        let brew = Self.isHomebrewInstall
        let alert = NSAlert()
        alert.messageText = loc("Elérhető új verzió") + ": \(release.version)"
        alert.informativeText = loc("Jelenlegi verzió") + ": \(current)"
            + (brew ? "\n\n" + loc("Frissítés Homebrew-val:") + "\n" + Self.brewCommand : "")
        alert.addButton(withTitle: loc("Kiadási oldal"))
        if brew { alert.addButton(withTitle: loc("brew-parancs másolása")) }
        alert.addButton(withTitle: loc("Kihagyom ezt a verziót"))
        alert.addButton(withTitle: loc("Később"))
        NSApp.activate(ignoringOtherApps: true)

        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        switch (index, brew) {
        case (0, _):
            NSWorkspace.shared.open(release.htmlURL)
        case (1, true):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.brewCommand, forType: .string)
        case (1, false), (2, true):
            UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
            available = nil
        default:
            break   // Later: the sidebar link stays
        }
    }

    // MARK: - Private

    private func fetchLatest(current: String) async throws -> ReleaseInfo {
        let url = UserDefaults.standard.string(forKey: Self.feedOverrideKey).flatMap(URL.init(string:))
            ?? UpdateCheck.latestReleaseURL
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TransmissionRemoteGUI/\(current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    /// Installed with the Homebrew cask (then `brew upgrade` is the right way to update).
    private static var isHomebrewInstall: Bool {
        ["/opt/homebrew/Caskroom/transmission-remote-gui-macos", "/usr/local/Caskroom/transmission-remote-gui-macos"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func inform(_ message: String, detail: String = "") {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
