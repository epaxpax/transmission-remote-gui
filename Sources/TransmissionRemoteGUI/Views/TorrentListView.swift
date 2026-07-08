import SwiftUI
import TransmissionKit

struct TorrentListView: View {
    @Environment(AppModel.self) private var model

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
                        effective: Localization.shared.effective   // header refreshes on language change
                    )
                }
            }
        }
        .navigationTitle(model.selectedServer?.name ?? "Transmission Remote GUI")
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
