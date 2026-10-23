import SwiftUI
import TransmissionKit

struct TorrentDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let selected = model.singleSelectedTorrent {
                // The detail fetch may still belong to the previous selection: only use it
                // when it is for this torrent, otherwise show the list row until it arrives.
                let torrent = model.detailTorrent.flatMap { $0.id == selected.id ? $0 : nil } ?? selected
                TabView {
                    GeneralTab(torrent: torrent)
                        .tabItem { Label(loc("Általános"), systemImage: "info.circle") }
                    FilesTab(torrent: torrent)
                        .tabItem { Label(loc("Fájlok"), systemImage: "doc.on.doc") }
                    PeersTab(peers: torrent.peers ?? [])
                        .tabItem { Label(loc("Peerek"), systemImage: "person.2") }
                    TrackersTab(trackers: torrent.trackerStats ?? [])
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
                SpeedLimitEditor(torrent: torrent)
                LabelsEditor(torrent: torrent)
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

/// Per-torrent speed-limit editor (KB/s), shown at the bottom of the General tab.
private struct SpeedLimitEditor: View {
    @Environment(AppModel.self) private var model
    let torrent: Torrent

    @State private var downOn = false
    @State private var down = 0
    @State private var upOn = false
    @State private var up = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
            Text(loc("Sebességkorlát (erre a torrentre)")).font(.callout.bold())
            limitRow(loc("Letöltés"), isOn: $downOn, value: $down)
            limitRow(loc("Feltöltés"), isOn: $upOn, value: $up)
            Button(loc("Alkalmaz")) {
                Task {
                    await model.setSpeedLimit(downEnabled: downOn, down: down, upEnabled: upOn, up: up,
                                              ids: .ids([.id(torrent.id)]))
                }
            }
            .padding(.top, 2)
        }
        .font(.callout)
        .onAppear { load() }
        // Reload when the selection changes AND when the detail fetch (the only one carrying
        // the limit fields) arrives for the same torrent.
        .onChange(of: limitKey) { _, _ in load() }
    }

    private func limitRow(_ label: String, isOn: Binding<Bool>, value: Binding<Int>) -> some View {
        HStack {
            Toggle(label, isOn: isOn).frame(width: 130, alignment: .leading)
            TextField("", value: value, format: .number)
                .frame(width: 70).multilineTextAlignment(.trailing).disabled(!isOn.wrappedValue)
            Text("kB/s").foregroundStyle(.secondary)
        }
    }

    private var limitKey: [Int] {
        [torrent.id,
         (torrent.downloadLimited ?? false) ? 1 : 0, torrent.downloadLimit ?? -1,
         (torrent.uploadLimited ?? false) ? 1 : 0, torrent.uploadLimit ?? -1]
    }

    private func load() {
        downOn = torrent.downloadLimited ?? false
        down = torrent.downloadLimit ?? 0
        upOn = torrent.uploadLimited ?? false
        up = torrent.uploadLimit ?? 0
    }
}

/// Label (category/tag) editor for the selected torrent — list of current labels
/// with remove buttons, plus an add field. Writes via torrent-set.
private struct LabelsEditor: View {
    @Environment(AppModel.self) private var model
    let torrent: Torrent
    @State private var newLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
            Text(loc("Címkék")).font(.callout.bold())
            ForEach(torrent.labels ?? [], id: \.self) { label in
                HStack(spacing: 6) {
                    Image(systemName: "tag").foregroundStyle(.secondary)
                    Text(label)
                    Spacer()
                    Button { remove(label) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField(loc("Új címke"), text: $newLabel).onSubmit { add() }
                Button(loc("Hozzáad")) { add() }
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .font(.callout)
    }

    private func add() {
        let t = newLabel.trimmingCharacters(in: .whitespaces)
        newLabel = ""
        guard !t.isEmpty else { return }
        var labels = torrent.labels ?? []
        guard !labels.contains(t) else { return }
        labels.append(t)
        Task { await model.setLabels(labels, ids: .ids([.id(torrent.id)])) }
    }

    private func remove(_ label: String) {
        let labels = (torrent.labels ?? []).filter { $0 != label }
        Task { await model.setLabels(labels, ids: .ids([.id(torrent.id)])) }
    }
}

// MARK: - Files

/// Hierarchical file list. The tree is rebuilt from every detail refresh, but node ids are
/// relative paths, so rows keep their identity and the expanded folders stay open.
private struct FilesTab: View {
    @Environment(AppModel.self) private var model
    let torrent: Torrent
    /// Expanded folder ids per torrent; a torrent without an entry uses the default.
    @State private var expandedByTorrent: [String: Set<String>] = [:]

    private var torrentKey: String { torrent.hashString ?? "#\(torrent.id)" }

    var body: some View {
        let files = torrent.files ?? []
        if files.isEmpty {
            Text(loc("Nincs fájlinformáció")).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let roots = FileTree.build(files: files, stats: torrent.fileStats)
            let expanded = expandedByTorrent[torrentKey] ?? FileTree.defaultExpanded(roots)
            let canShowInFinder = TorrentRowMenu.isVisible(.showInFinder,
                hasPathMappings: !(model.selectedServer?.pathMappings ?? []).isEmpty)
            List(FileTree.visibleRows(roots, expanded: expanded)) { node in
                FileTreeRow(node: node,
                            isExpanded: expanded.contains(node.id),
                            toggleExpanded: { toggleExpanded(node, current: expanded) },
                            setWanted: { setWanted(node, wanted: $0) },
                            setPriority: { setPriority(node, priority: $0) })
                    .contextMenu {
                        if canShowInFinder {
                            Button(loc("Megjelenítés a Finderben")) { showInFinder(node) }
                        }
                    }
            }
            .accessibilityIdentifier("files.list")
        }
    }

    private func toggleExpanded(_ node: FileTreeNode, current: Set<String>) {
        var next = current
        if next.contains(node.id) { next.remove(node.id) } else { next.insert(node.id) }
        expandedByTorrent[torrentKey] = next
    }

    /// One `torrent-set` for the file or for every file below the folder.
    private func setWanted(_ node: FileTreeNode, wanted: Bool) {
        let args = FileTree.wantedArgs(torrentID: torrent.id, indices: node.fileIndices, wanted: wanted)
        Task { await model.applyTorrentSet(args) }
    }

    private func setPriority(_ node: FileTreeNode, priority: TorrentFileStat.Priority) {
        let args = FileTree.priorityArgs(torrentID: torrent.id, indices: node.fileIndices, priority: priority)
        Task { await model.applyTorrentSet(args) }
    }

    private func showInFinder(_ node: FileTreeNode) {
        guard let serverID = model.selectedServerID else { return }
        let torrent = torrent
        Task { await model.showInFinder(torrent, entry: node.path, isFile: !node.isDirectory, serverID: serverID) }
    }
}

private struct FileTreeRow: View {
    let node: FileTreeNode
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let setWanted: (Bool) -> Void
    let setPriority: (TorrentFileStat.Priority) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(node.depth) * 16, height: 1)
            if node.isDirectory {
                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isExpanded ? loc("Összecsukás") : loc("Kibontás"))
                .accessibilityIdentifier("files.disclosure." + node.id)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }

            if let wanted = node.wanted {
                // Two sources that disagree render the native "mixed" checkbox state;
                // only the first one sends the change, so a click is one `torrent-set`.
                Toggle(sources: [
                    Binding(get: { wanted != .off }, set: { setWanted($0) }),
                    Binding(get: { wanted == .on }, set: { _ in }),
                ], isOn: \.self) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("files.wanted." + node.id)
            }

            Image(systemName: node.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(Format.size(node.length))
                    Text(Format.percent(node.progress))
                    if node.isDirectory {
                        Text(node.fileIndices.count == 1 ? loc("1 fájl") : "\(node.fileIndices.count) " + loc("fájl"))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let priority = node.priority {
                Picker("", selection: Binding(
                    get: { priority },
                    set: { if case .uniform(let value) = $0 { setPriority(value) } }
                )) {
                    if priority == .mixed {
                        Text(loc("Vegyes")).tag(FileTreeNode.PriorityState.mixed)
                    }
                    Text(loc("Alacsony")).tag(FileTreeNode.PriorityState.uniform(.low))
                    Text(loc("Normál")).tag(FileTreeNode.PriorityState.uniform(.normal))
                    Text(loc("Magas")).tag(FileTreeNode.PriorityState.uniform(.high))
                }
                .labelsHidden()
                .frame(width: 100)
                .accessibilityIdentifier("files.priority." + node.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("files.row." + node.id)
    }
}

// MARK: - Peers

private struct PeersTab: View {
    let peers: [Peer]
    private let geo = GeoIPStore.shared
    // The chosen column survives switching torrents / tabs and restarts.
    @AppStorage("peerSortColumn") private var sortColumn = "address"
    @AppStorage("peerSortAscending") private var sortAscending = true

    /// One table row: the peer plus its looked-up country.
    struct Row: Identifiable {
        let peer: Peer
        let country: String?
        let countryName: String
        var id: String { peer.address }
        var address: AddressSortKey { peer.addressSortKey }
        var client: String { peer.clientSortKey }
        var progress: Double { peer.progress }
        var down: Int { peer.rateToClient }
        var up: Int { peer.rateToPeer }
        /// Peers without a known country sort after the rest.
        var countrySort: String { country == nil ? "\u{10FFFF}" : countryName }
    }

    private static let columns: [(String, KeyPathComparator<Row>)] = [
        ("country", KeyPathComparator(\Row.countrySort)), ("address", KeyPathComparator(\Row.address)),
        ("client", KeyPathComparator(\Row.client)), ("progress", KeyPathComparator(\Row.progress)),
        ("down", KeyPathComparator(\Row.down)), ("up", KeyPathComparator(\Row.up)),
    ]

    private var sortOrder: Binding<[KeyPathComparator<Row>]> {
        Binding {
            var c = Self.columns.first { $0.0 == sortColumn }?.1 ?? KeyPathComparator(\Row.address)
            c.order = sortAscending ? .forward : .reverse
            return [c]
        } set: { order in
            guard let c = order.first else { return }
            sortColumn = Self.columns.first { $0.1.keyPath == c.keyPath }?.0 ?? "address"
            sortAscending = c.order == .forward
        }
    }

    private var rows: [Row] {
        let locale = Localization.shared.locale
        return peers.map { peer in
            let cc = geo.country(for: peer.address)
            return Row(peer: peer, country: cc, countryName: cc.flatMap { locale.localizedString(forRegionCode: $0) } ?? cc ?? "")
        }.sorted(using: sortOrder.wrappedValue)
    }

    var body: some View {
        Group {
            if peers.isEmpty {
                Text(loc("Nincsenek kapcsolódott peerek")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Table(rows, sortOrder: sortOrder) {
                        TableColumn(loc("Ország"), value: \.countrySort) { row in
                            Text(row.country.flatMap(CountryFlag.emoji) ?? "")
                                .help(row.countryName)
                                .accessibilityLabel(row.countryName)
                        }.width(min: 44, ideal: 64, max: 90)
                        TableColumn(loc("Cím"), value: \.address) { Text($0.peer.address).font(.caption.monospaced()) }
                        TableColumn(loc("Kliens"), value: \.client) { Text($0.peer.clientName ?? "—").lineLimit(1) }
                        TableColumn(loc("Kész"), value: \.progress) { Text(Format.percent($0.progress)) }.width(50)
                        TableColumn("↓", value: \.down) { Text(Format.rate($0.down)) }.width(80)
                        TableColumn("↑", value: \.up) { Text(Format.rate($0.up)) }.width(80)
                    }
                    if geo.table != nil {
                        // Required by the CC BY 4.0 licence of the country data.
                        Link(loc("Országadatok: DB-IP"), destination: URL(string: "https://db-ip.com")!)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { geo.loadIfNeeded() }
    }
}

// MARK: - Trackers

private struct TrackersTab: View {
    let trackers: [TrackerStat]
    @State private var sortOrder = [KeyPathComparator(\TrackerStat.displayHost)]

    var body: some View {
        if trackers.isEmpty {
            Text(loc("Nincs tracker információ")).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(trackers.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn(loc("Tracker"), value: \.displayHost) { Text($0.displayHost).lineLimit(1) }
                TableColumn(loc("Állapot"), value: \.resultSortKey) {
                    Text(Localization.shared.trackerResult($0.lastAnnounceResult)).lineLimit(1)
                }
                TableColumn(loc("Seedek"), value: \.seederSortKey) { t in Text(count(t.seederCount)) }.width(60)
                TableColumn(loc("Leecherek"), value: \.leecherSortKey) { t in Text(count(t.leecherCount)) }.width(70)
            }
        }
    }

    private func count(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return "\(value)"
    }
}
