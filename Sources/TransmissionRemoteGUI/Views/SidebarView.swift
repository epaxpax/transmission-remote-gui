import SwiftUI
import TransmissionKit

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List {
            Section(loc("Szűrők")) {
                ForEach(TorrentFilter.allCases) { filter in
                    Button {
                        model.filter = filter
                    } label: {
                        HStack {
                            Label(loc(filter.title), systemImage: filter.systemImage)
                            Spacer()
                            if model.isConnected {
                                Text("\(model.count(for: filter))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(model.filter == filter ? Color.accentColor.opacity(0.18) : Color.clear)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { statusBar }
    }

    @ViewBuilder
    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider()

            // Active server + connection state (servers are managed in Settings, ⌘,).
            HStack(spacing: 6) {
                Image(systemName: model.isConnected ? "network" : "network.slash")
                    .foregroundStyle(model.isConnected ? .green : .secondary)
                if let server = model.selectedServer {
                    Text(server.name).lineLimit(1)
                    Spacer()
                    if !connectionKey.isEmpty {
                        Text(loc(connectionKey)).foregroundStyle(.secondary)
                    }
                } else {
                    Text(loc("Nincs szerver — ⌘, a beállításokhoz")).foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let stats = model.sessionStats {
                HStack(spacing: 10) {
                    Label(Format.rateOrZero(stats.downloadSpeed ?? 0), systemImage: "arrow.down")
                    Label(Format.rateOrZero(stats.uploadSpeed ?? 0), systemImage: "arrow.up")
                    Spacer()
                    if let version = model.sessionInfo?.version {
                        // The SERVER's Transmission daemon version (NOT the app's!) — without the build hash.
                        Text("Transmission " + version.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces))
                            .foregroundStyle(.secondary)
                            .help(loc("A szerveren futó Transmission daemon verziója"))
                    }
                }

                // Compact speed graph (down/up over time).
                if model.speedHistory.count > 1 {
                    SpeedChartView(samples: model.speedHistory, showBaseline: false)
                        .frame(height: 34)
                }
            }
            if let free = model.freeSpace, free > 0 {
                Label("\(loc("Szabad hely")): \(Format.size(free))", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    /// Short connection-state key (Hungarian); the body passes it through `loc()`.
    private var connectionKey: String {
        switch model.connection {
        case .connected: return ""
        case .connecting: return "Csatlakozás…"
        case .disconnected: return "Nincs kapcsolat"
        case .failed: return "Hiba"
        }
    }
}
