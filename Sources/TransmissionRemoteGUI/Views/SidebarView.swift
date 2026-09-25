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
                    .accessibilityLabel(loc(filter.title))
                    .accessibilityIdentifier("sidebar.filter.\(filter.rawValue)")
                    .accessibilityValue(model.isConnected ? "\(model.count(for: filter))" : "")
                    .listRowBackground(model.filter == filter ? Color.accentColor.opacity(0.18) : Color.clear)
                }
            }

            // Value filters — each section only appears when it can actually narrow the list.
            // They combine with the status filter above and with each other.
            if !model.labelGroups.isEmpty || model.labelFilter != nil {
                groupSection("Címkék", idPrefix: "label", icon: "tag", entries: model.labelGroups, selection: $model.labelFilter)
            }
            if !model.trackerGroups.isEmpty || model.trackerFilter != nil {
                groupSection("Trackerek", idPrefix: "tracker", icon: "antenna.radiowaves.left.and.right",
                             entries: model.trackerGroups, selection: $model.trackerFilter)
            }
            if model.folderGroups.count > 1 || model.folderFilter != nil {
                let titles = SidebarGroups.folderTitles(model.folderGroups.map(\.value))
                groupSection("Mappák", idPrefix: "folder", icon: "folder", entries: model.folderGroups,
                             selection: $model.folderFilter, title: { titles[$0] ?? $0 }, help: { $0 })
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { statusBar }
    }

    /// One value-filter section. Clicking the selected row again clears the filter. A
    /// selected value that no torrent carries any more stays listed (count 0), so the filter
    /// can always be switched off from where it was switched on.
    @ViewBuilder
    private func groupSection(_ header: String, idPrefix: String, icon: String, entries: [SidebarGroups.Entry],
                              selection: Binding<String?>,
                              title: @escaping (String) -> String = { $0 },
                              help: @escaping (String) -> String? = { _ in nil }) -> some View {
        let rows = selection.wrappedValue.map { sel in
            entries.contains { $0.value == sel } ? entries : entries + [SidebarGroups.Entry(value: sel, count: 0)]
        } ?? entries
        Section(loc(header)) {
            ForEach(rows, id: \.value) { entry in
                Button {
                    selection.wrappedValue = selection.wrappedValue == entry.value ? nil : entry.value
                } label: {
                    HStack {
                        Label(title(entry.value), systemImage: icon).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(entry.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospacedDigit())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help(entry.value) ?? "")
                .accessibilityLabel(title(entry.value))
                .accessibilityIdentifier("sidebar.\(idPrefix).\(entry.value)")
                .accessibilityValue("\(entry.count)")
                .listRowBackground(selection.wrappedValue == entry.value ? Color.accentColor.opacity(0.18) : Color.clear)
            }
        }
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
