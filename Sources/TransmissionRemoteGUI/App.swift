import SwiftUI
import AppKit
import TransmissionKit

@main
struct TransmissionRemoteGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    /// Identifier of the main window — used to reopen it from the menu bar (`openWindow`).
    static let mainWindowID = "main"

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
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

        // Menu bar (tray) icon: shows down/up speed in the bar; the window can be brought up from the menu.
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
    }
}

/// Label shown in the menu bar: icon + current down/up speed.
private struct MenuBarLabel: View {
    let model: AppModel
    var body: some View {
        let down = model.sessionStats?.downloadSpeed ?? 0
        let up = model.sessionStats?.uploadSpeed ?? 0
        HStack(spacing: 3) {
            Image(nsImage: AppIcon.menuBarIcon())
            if model.isConnected {
                Text("↓\(short(down)) ↑\(short(up))").font(.caption.monospacedDigit())
            }
        }
    }

    /// Compact speed for the menu bar (e.g. "1.2M").
    private func short(_ bytesPerSec: Int) -> String {
        guard bytesPerSec > 0 else { return "0" }
        let kb = Double(bytesPerSec) / 1024
        if kb < 1000 { return "\(Int(kb))k" }
        return String(format: "%.1fM", kb / 1024)
    }
}

/// Drop-down menu of the menu bar icon.
private struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.isConnected, let stats = model.sessionStats {
            Text(loc("Letöltés") + ": " + Format.rateOrZero(stats.downloadSpeed ?? 0))
            Text(loc("Feltöltés") + ": " + Format.rateOrZero(stats.uploadSpeed ?? 0))
            if let free = model.freeSpace, free > 0 {
                Text(loc("Szabad hely") + ": " + Format.size(free))
            }
            Divider()
        } else {
            Text(loc("Nincs kapcsolat"))
            Divider()
        }
        Button(loc("Ablak előtérbe")) { showWindow() }
        Toggle(loc("Dock-ikon megjelenítése"), isOn: $model.showDockIcon)
        Divider()
        Button(loc("Kilépés")) { NSApp.terminate(nil) }
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock icon visibility is decided by the saved setting (toggleable from the menu bar).
        let showDock = (UserDefaults.standard.object(forKey: AppModel.showDockIconKey) as? Bool) ?? true
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        NSApp.applicationIconImage = AppIcon.dockIcon()
        NSApp.activate(ignoringOtherApps: true)
        Notifier.requestAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Because of the menu bar icon, do not quit when the last window closes (reopenable from the tray).
        false
    }
}
