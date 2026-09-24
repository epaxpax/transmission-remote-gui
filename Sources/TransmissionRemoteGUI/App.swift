import SwiftUI
import AppKit
import TransmissionKit

@main
struct TransmissionRemoteGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Owned by the app delegate, so Finder / browser open events (which AppKit delivers to the
    /// delegate, possibly before any window exists) can reach it.
    private var model: AppModel { appDelegate.model }

    /// Identifier of the main window — used to reopen it from the menu bar (`openWindow`).
    static let mainWindowID = "main"

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView()
                .environment(model)

                .frame(minWidth: 960, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        // Open events (.torrent files, magnet links) are handled by `AppDelegate`; without this
        // SwiftUI would additionally open a new main window for each one.
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(after: .toolbar) {
                Button(loc("Nagyítás")) { model.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button(loc("Kicsinyítés")) { model.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button(loc("Eredeti méret")) { model.zoomReset() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 520, height: 460)
        }

        // Menu bar (tray) icon: shows down/up speed in the bar; the popover shows a live
        // speed graph + stats (Stats-app style) and window/quit controls.
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model, delegate: appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Label shown in the menu bar: icon + current down/up speed.
private struct MenuBarLabel: View {
    let model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let down = model.sessionStats?.downloadSpeed ?? 0
        let up = model.sessionStats?.uploadSpeed ?? 0
        HStack(spacing: 3) {
            Image(nsImage: AppIcon.menuBarIcon())
            if model.isConnected {
                Text("↓\(short(down)) ↑\(short(up))").font(.caption.monospacedDigit())
            }
        }
        // The menu bar label is rendered from launch on, even when no window exists — so it is
        // where the app delegate gets a way to (re)open the main window for open events.
        .task { delegate.openMainWindow = { openWindow(id: TransmissionRemoteGUIApp.mainWindowID) } }
    }

    /// Compact speed for the menu bar (e.g. "1.2M").
    private func short(_ bytesPerSec: Int) -> String {
        guard bytesPerSec > 0 else { return "0" }
        let kb = Double(bytesPerSec) / 1024
        if kb < 1000 { return "\(Int(kb))k" }
        return String(format: "%.1fM", kb / 1024)
    }
}

/// Popover content of the menu bar icon: live speed graph + stats, and controls.
private struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isConnected, let stats = model.sessionStats {
                HStack(spacing: 28) {
                    speed(loc("Letöltés"), Format.rateOrZero(stats.downloadSpeed ?? 0), .green)
                    speed(loc("Feltöltés"), Format.rateOrZero(stats.uploadSpeed ?? 0), .blue)
                }
                if model.speedHistory.count > 1 {
                    SpeedChartView(samples: model.speedHistory, showBaseline: false)
                        .frame(height: 56)
                }
                if let free = model.freeSpace, free > 0 {
                    Text(loc("Szabad hely") + ": " + Format.size(free))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(loc("Nincs kapcsolat")).foregroundStyle(.secondary)
            }

            Divider()
            Button { showWindow() } label: { Label(loc("Ablak előtérbe"), systemImage: "macwindow") }
                .buttonStyle(.plain)
            Toggle(loc("Dock-ikon megjelenítése"), isOn: $model.showDockIcon)
                .toggleStyle(.checkbox)
            Divider()
            Button { NSApp.terminate(nil) } label: { Label(loc("Kilépés"), systemImage: "power") }
                .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func speed(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Brings the main window to the front; if no live window remains (e.g. it was closed
    /// while the app lived only in the menu bar), reopens the `WindowGroup`.
    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.canBecomeMain }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: TransmissionRemoteGUIApp.mainWindowID)
        }
    }
}

/// An app launched from SwiftPM (without a bundle) must request the `.regular` activation
/// policy manually, otherwise it gets no focus and no Dock icon appears.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    /// `.torrent` files (Finder "Open" / "Open With" / double-click) and `magnet:` links
    /// (clicked in a browser).
    func application(_ application: NSApplication, open urls: [URL]) {
        model.openIncoming(urls)
        showMainWindow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock icon visibility is decided by the saved setting (toggleable from the menu bar).
        let showDock = (UserDefaults.standard.object(forKey: AppModel.showDockIconKey) as? Bool) ?? true
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        NSApp.applicationIconImage = AppIcon.dockIcon()
        NSApp.activate(ignoringOtherApps: true)
        Notifier.requestAuthorization()
    }

    /// Opens the main `WindowGroup` window (set by the menu bar label once it is rendered).
    var openMainWindow: (() -> Void)? {
        didSet { if wantsMainWindow { showMainWindow() } }
    }
    private var wantsMainWindow = false

    /// Brings the main window forward. Needed because the main scene does not handle open
    /// events: on a cold launch by double-clicking a `.torrent`, SwiftUI opens no window at all.
    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            wantsMainWindow = false
            win.makeKeyAndOrderFront(nil)
        } else if let openMainWindow {
            wantsMainWindow = false
            openMainWindow()
        } else {
            wantsMainWindow = true   // label not rendered yet; `openMainWindow`'s didSet retries
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Because of the menu bar icon, do not quit when the last window closes (reopenable from the tray).
        false
    }
}
