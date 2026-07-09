import Foundation
import UserNotifications

/// Local (macOS) notifications for torrent events.
///
/// `UNUserNotificationCenter` cannot be used without a bundle identifier (it crashes), so
/// every call is a no-op when the app is not running from a bundle (e.g. under `swift run`
/// during development). From the `.app` bundle it works.
enum Notifier {
    private static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// Requests notification permission — call once, at launch.
    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Notification about a finished (download complete) torrent.
    static func torrentFinished(name: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Torrent kész"
        content.body = name
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
