import SwiftUI
import UniformTypeIdentifiers
import TransmissionKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false
    @State private var showingStats = false
    @State private var showingRSS = false
    @State private var removeConfirm = false
    /// Whether the Details inspector is visible. Hidden by default; toggled via ⌘I / toolbar button. Persistent.
    @AppStorage("showInspector") private var showInspector = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            // Details panel lives INSIDE the detail area (an HSplitView), so its divider
            // stays below the toolbar and the table shares the width instead of the
            // inspector overlapping the toolbar / not shrinking the list.
            HSplitView {
                TorrentListView()
                    .frame(minWidth: 420)
                    .searchable(text: $model.searchText, placement: .toolbar, prompt: "Keresés")
                if showInspector {
                    TorrentDetailView()
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)
                }
            }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAdd) {
            AddTorrentView()
        }
        .sheet(isPresented: $showingStats) {
            StatisticsView().environment(model)
        }
        .sheet(isPresented: $showingRSS) {
            RSSView().environment(model)
        }
        .confirmationDialog(
            loc("Biztosan törlöd a kijelölt torrent(eket)?"),
            isPresented: $removeConfirm,
            titleVisibility: .visible
        ) {
            Button(loc("Törlés a listából"), role: .destructive) {
                Task { await model.remove(deleteData: false) }
            }
            Button(loc("Törlés az adatokkal együtt"), role: .destructive) {
                Task { await model.remove(deleteData: true) }
            }
            Button(loc("Mégse"), role: .cancel) {}
        }
        .dynamicTypeSize(DynamicTypeSize.forScale(model.uiScale))
        .onDrop(of: [.fileURL, .url, .text], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .task { model.autoConnectIfNeeded() }   // connect to the most recent server at launch
    }

    /// Adds a dragged-in `.torrent` file / magnet link / URL. Calls the existing add API.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.isConnected else { return false }
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL,
                          url.pathExtension.lowercased() == "torrent" else { return }
                    Task { @MainActor in await model.addTorrentFile(url) }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in await model.add(filename: url.absoluteString) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard value.hasPrefix("magnet:") || value.hasPrefix("http") else { return }
                    Task { @MainActor in await model.add(filename: value) }
                }
            }
        }
        return handled
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showingAdd = true
            } label: {
                Label(loc("Hozzáadás"), systemImage: "plus")
            }
            .disabled(!model.isConnected)

            Button {
                Task { await model.start() }
            } label: {
                Label(loc("Indítás"), systemImage: "play.fill")
            }
            .disabled(model.selection.isEmpty)

            Button {
                Task { await model.stop() }
            } label: {
                Label(loc("Leállítás"), systemImage: "pause.fill")
            }
            .disabled(model.selection.isEmpty)

            Button(role: .destructive) {
                removeConfirm = true
            } label: {
                Label(loc("Törlés"), systemImage: "trash")
            }
            .disabled(model.selection.isEmpty)

            Button {
                Task { await model.refresh() }
            } label: {
                Label(loc("Frissítés"), systemImage: "arrow.clockwise")
            }
            .disabled(!model.isConnected)
        }

        // More actions on the selection (verify / reannounce).
        ToolbarItem {
            Menu {
                Button { Task { await model.verify() } } label: {
                    Label(loc("Ellenőrzés (verify)"), systemImage: "checkmark.shield")
                }
                Button { Task { await model.reannounce() } } label: {
                    Label(loc("Újrabejelentés a trackernek"), systemImage: "dot.radiowaves.up.forward")
                }
                Divider()
                Button { Task { await model.setSequential(on: true) } } label: {
                    Label(loc("Streaming (sorrendi) letöltés be"), systemImage: "play.rectangle.on.rectangle")
                }
                .disabled(!model.supportsSequential)
                Button { Task { await model.setSequential(on: false) } } label: {
                    Label(loc("Streaming letöltés ki"), systemImage: "stop.rectangle")
                }
                .disabled(!model.supportsSequential)
                if !model.supportsSequential {
                    Text(loc("Sorrendi letöltéshez Transmission 4.1+ szükséges"))
                }
            } label: {
                Label(loc("Egyéb műveletek"), systemImage: "ellipsis.circle")
            }
            .disabled(model.selection.isEmpty)
        }

        // Statistics panel (speed graph + totals).
        ToolbarItem {
            Button { showingStats = true } label: {
                Label(loc("Statisztika"), systemImage: "chart.line.uptrend.xyaxis")
            }
            .disabled(!model.isConnected)
        }

        // RSS auto-downloader manager.
        ToolbarItem {
            Button { showingRSS = true } label: {
                Label(loc("RSS auto-letöltő"), systemImage: "dot.radiowaves.up.forward")
            }
        }

        // Alternative ("turtle") speed limit on/off — global session toggle.
        ToolbarItem {
            Button {
                model.toggleAltSpeed()
            } label: {
                Label(loc("Turtle mód"), systemImage: model.isAltSpeedOn ? "tortoise.fill" : "tortoise")
            }
            .disabled(!model.isConnected)
            .foregroundStyle(model.isAltSpeedOn ? Color.green : Color.primary)
            .help(model.isAltSpeedOn ? loc("Alternatív sebességkorlát BE — kikapcsolás") : loc("Alternatív sebességkorlát (turtle) bekapcsolása"))
        }

        // Opens/closes the Details inspector (right-hand panel).
        ToolbarItem {
            Button {
                showInspector.toggle()
            } label: {
                Label(loc("Részletek"), systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: .command)
            .help(loc("Részletek panel megjelenítése/elrejtése (⌘I)"))
        }
    }
}

extension DynamicTypeSize {
    /// Maps the continuous UI zoom to the nearest Dynamic Type step (for SwiftUI texts).
    static func forScale(_ s: Double) -> DynamicTypeSize {
        switch s {
        case ..<0.9: return .small
        case ..<1.05: return .medium
        case ..<1.2: return .large
        case ..<1.35: return .xLarge
        case ..<1.5: return .xxLarge
        case ..<1.75: return .xxxLarge
        case ..<2.0: return .accessibility1
        case ..<2.3: return .accessibility2
        default: return .accessibility3
        }
    }
}
