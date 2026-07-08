import SwiftUI
import TransmissionKit

struct TorrentDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let torrent = model.singleSelectedTorrent {
                TabView {
                    GeneralTab(torrent: model.detailTorrent ?? torrent)
                        .tabItem { Label(loc("Általános"), systemImage: "info.circle") }
                    FilesTab(torrent: model.detailTorrent ?? torrent)
                        .tabItem { Label(loc("Fájlok"), systemImage: "doc.on.doc") }
                    PeersTab(peers: (model.detailTorrent ?? torrent).peers ?? [])
                        .tabItem { Label(loc("Peerek"), systemImage: "person.2") }
                    TrackersTab(trackers: (model.detailTorrent ?? torrent).trackerStats ?? [])
                        .tabItem { Label(loc("Trackerek"), systemImage: "antenna.radiowaves.left.and.right") }
                }
                .padding(8)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text(model.selection.count > 1 ? loc("Több torrent kijelölve") : loc("Nincs kijelölt torrent"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: model.selection) {
            await model.refreshDetail()
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    let torrent: Torrent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                row("Név", torrent.displayName)
                row("Méret", Format.size(torrent.totalSize ?? 0))
                row("Kész", Format.percent(torrent.progress))
                row("Letöltve", Format.size(torrent.downloadedEver ?? 0))
                row("Feltöltve", Format.size(torrent.uploadedEver ?? 0))
                row("Arány", Format.ratio(torrent.ratio))
                row("Letöltési ráta", Format.rateOrZero(torrent.downloadRate))
                row("Feltöltési ráta", Format.rateOrZero(torrent.uploadRate))
                row("ETA", Format.eta(torrent.eta ?? -1))
                row("Peerek", "\(torrent.connectedPeers) · ↑\(torrent.sendingPeers) ↓\(torrent.receivingPeers)")
                if let dir = torrent.downloadDir { row("Mappa", dir) }
                if let date = torrent.addedDateValue {
                    row("Hozzáadva", date.formatted(date: .abbreviated, time: .shortened))
                }
                if let hash = torrent.hashString { row("Hash", hash) }
                if let comment = torrent.comment, !comment.isEmpty { row("Megjegyzés", comment) }
                if torrent.hasError, let err = torrent.errorString {
                    row("Hiba", err, color: .red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func row(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack(alignment: .top) {
            Text(loc(label)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).foregroundStyle(color).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}

// MARK: - Files

private struct FilesTab: View {
    @Environment(AppModel.self) private var model
    let torrent: Torrent

    var body: some View {
        let files = torrent.files ?? []
        let stats = torrent.fileStats ?? []
        if files.isEmpty {
            Text(loc("Nincs fájlinformáció")).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    let stat = index < stats.count ? stats[index] : nil
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { stat?.wanted ?? true },
                            set: { wanted in setWanted(index: index, wanted: wanted) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).lineLimit(1).truncationMode(.middle)
                            HStack(spacing: 6) {
                                Text(Format.size(file.length))
                                Text(Format.percent(file.progress))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let stat {
                            Picker("", selection: Binding(
                                get: { stat.priorityValue },
                                set: { setPriority(index: index, priority: $0) }
                            )) {
                                Text(loc("Alacsony")).tag(TorrentFileStat.Priority.low)
                                Text(loc("Normál")).tag(TorrentFileStat.Priority.normal)
                                Text(loc("Magas")).tag(TorrentFileStat.Priority.high)
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                    }
                }
            }
        }
    }

    private func setWanted(index: Int, wanted: Bool) {
        var args = TorrentSetArgs(ids: .ids([.id(torrent.id)]))
        if wanted { args.filesWanted = [index] } else { args.filesUnwanted = [index] }
        Task { await model.applyTorrentSet(args) }
    }

    private func setPriority(index: Int, priority: TorrentFileStat.Priority) {
        var args = TorrentSetArgs(ids: .ids([.id(torrent.id)]))
        switch priority {
        case .low: args.priorityLow = [index]
        case .normal: args.priorityNormal = [index]
        case .high: args.priorityHigh = [index]
        }
        Task { await model.applyTorrentSet(args) }
    }
}

// MARK: - Peers

private struct PeersTab: View {
    let peers: [Peer]

    var body: some View {
        if peers.isEmpty {
            Text(loc("Nincsenek kapcsolódott peerek")).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(peers) {
                TableColumn(loc("Cím")) { Text($0.address).font(.caption.monospaced()) }
                TableColumn(loc("Kliens")) { Text($0.clientName ?? "—").lineLimit(1) }
                TableColumn(loc("Kész")) { Text(Format.percent($0.progress)) }.width(50)
                TableColumn("↓") { Text(Format.rate($0.rateToClient)) }.width(80)
                TableColumn("↑") { Text(Format.rate($0.rateToPeer)) }.width(80)
            }
        }
    }
}

// MARK: - Trackers

private struct TrackersTab: View {
    let trackers: [TrackerStat]

    var body: some View {
        if trackers.isEmpty {
            Text(loc("Nincs tracker információ")).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(trackers) {
                TableColumn(loc("Tracker")) { Text($0.displayHost).lineLimit(1) }
                TableColumn(loc("Állapot")) { Text($0.lastAnnounceResult ?? "—").lineLimit(1) }
                TableColumn(loc("Seedek")) { t in Text(count(t.seederCount)) }.width(60)
                TableColumn(loc("Leecherek")) { t in Text(count(t.leecherCount)) }.width(70)
            }
        }
    }

    private func count(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return "\(value)"
    }
}
