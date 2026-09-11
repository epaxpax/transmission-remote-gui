import SwiftUI
import AppKit
import TransmissionKit

struct TorrentListView: View {
    @Environment(AppModel.self) private var model

    @State private var moveRequest: MoveRequest?
    @State private var renameRequest: RenameRequest?
    @State private var removeRequest: RemoveRequest?

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.connection {
            case .disconnected:
                placeholder(icon: "network.slash", title: loc("Nincs kapcsolat"),
                            subtitle: loc("Válassz szervert a Beállításokban (⌘,)"))
            case .connecting:
                ProgressView(loc("Csatlakozás…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                placeholder(icon: "exclamationmark.triangle", title: loc("Hiba"), subtitle: message)
            case .connected:
                if model.displayedTorrents.isEmpty {
                    placeholder(icon: "tray", title: loc("Nincs torrent"),
                                subtitle: loc("Ehhez a szűrőhöz nincs megjeleníthető torrent."))
                } else {
                    TorrentTableView(
                        torrents: model.displayedTorrents,
                        selection: $model.selection,
                        sortOrder: $model.sortOrder,
                        scale: model.uiScale,
                        effective: Localization.shared.effective,  // header refreshes on language change
                        onCommand: handle
                    )
                }
            }
        }
        .navigationTitle(model.selectedServer?.name ?? "Transmission Remote GUI")
        .sheet(item: $moveRequest) { request in
            MoveTorrentView(torrents: request.torrents) { location, move in
                Task { await model.setLocation(location, move: move, ids: request.ids) }
            }
        }
        .sheet(item: $renameRequest) { request in
            RenameTorrentView(torrent: request.torrent) { newName in
                Task { await model.rename(id: request.torrent.id, from: request.oldName, to: newName) }
            }
        }
        .confirmationDialog(
            loc("Biztosan törlöd a kijelölt torrent(eket)?"),
            isPresented: Binding(get: { removeRequest != nil },
                                 set: { if !$0 { removeRequest = nil } }),
            titleVisibility: .visible,
            presenting: removeRequest
        ) { request in
            Button(request.deleteData ? loc("Törlés az adatokkal együtt") : loc("Törlés a listából"),
                   role: .destructive) {
                Task { await model.remove(ids: request.ids, deleteData: request.deleteData) }
            }
            Button(loc("Mégse"), role: .cancel) {}
        }
        .alert(loc("A művelet nem sikerült"),
               isPresented: Binding(get: { model.actionError != nil },
                                    set: { if !$0 { model.actionError = nil } }),
               presenting: model.actionError) { _ in
            Button(loc("OK"), role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: Context menu commands

    /// Dispatches a context-menu command. The targets come from the menu itself, so a
    /// right-click never acts on a stale selection.
    private func handle(_ command: TorrentRowCommand, _ targets: [Torrent]) {
        guard !targets.isEmpty else { return }
        let ids = RPCIds.ids(targets.map { RPCIdentifier.id($0.id) })

        switch command {
        case .start:
            Task { await model.start(ids: ids) }
        case .stop:
            Task { await model.stop(ids: ids) }
        case .verify:
            Task { await model.verify(ids: ids) }
        case .reannounce:
            Task { await model.reannounce(ids: ids) }
        case .move:
            moveRequest = MoveRequest(torrents: targets)
        case .rename:
            // Enablement guarantees a single, named torrent; the guard keeps that honest.
            guard let torrent = targets.first, let oldName = torrent.name, targets.count == 1 else { return }
            renameRequest = RenameRequest(torrent: torrent, oldName: oldName)
        case .copyName:
            copyToPasteboard(targets.compactMap(\.name).joined(separator: "\n"))
        case .copyHash:
            copyToPasteboard(targets.compactMap(\.hashString).joined(separator: "\n"))
        case .removeKeepData:
            removeRequest = RemoveRequest(torrents: targets, deleteData: false)
        case .removeWithData:
            removeRequest = RemoveRequest(torrents: targets, deleteData: true)
        }
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func placeholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pending modal requests
//
// Each carries its own targets, so the sheet/dialog acts on the rows the menu was
// opened for even if the selection changes while it is up.

private struct MoveRequest: Identifiable {
    let id = UUID()
    let torrents: [Torrent]
    var ids: RPCIds { .ids(torrents.map { RPCIdentifier.id($0.id) }) }
}

private struct RenameRequest: Identifiable {
    let id = UUID()
    let torrent: Torrent
    let oldName: String
}

private struct RemoveRequest: Identifiable {
    let id = UUID()
    let torrents: [Torrent]
    let deleteData: Bool
    var ids: RPCIds { .ids(torrents.map { RPCIdentifier.id($0.id) }) }
}
