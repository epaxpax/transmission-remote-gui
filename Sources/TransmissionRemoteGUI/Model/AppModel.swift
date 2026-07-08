import Foundation
import AppKit
import Observation
import TransmissionKit

@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    // Servers
    var servers: [ServerConfig]
    var selectedServerID: ServerConfig.ID? {
        didSet { persistSelectedServer() }   // most recently used server, for auto-connect
    }
    private static let selectedServerKey = "selectedServerID"

    // Connection / data
    private(set) var connection: ConnectionState = .disconnected
    private(set) var torrents: [Torrent] = [] {
        didSet { recomputeCounts(); recomputeDisplayed() }
    }
    /// The displayed (filtered + sorted) list — cached, recomputed only when the
    /// input changes, so the `Table` does not re-sort on every render.
    private(set) var displayedTorrents: [Torrent] = []
    /// Per-filter counts for the sidebar — populated when torrents change.
    private(set) var filterCounts: [TorrentFilter: Int] = [:]
    /// The selected torrent with extended fields (files/peers/trackers) — for the detail view.
    private(set) var detailTorrent: Torrent?
    private(set) var sessionInfo: SessionInfo?
    private(set) var sessionStats: SessionStats?
    /// Free disk space (bytes) on the download directory — on the daemon's machine.
    private(set) var freeSpace: Int?

    // UI state
    var filter: TorrentFilter = .all { didSet { recomputeDisplayed() } }
    var searchText: String = "" { didSet { recomputeDisplayed() } }
    var selection: Set<Int> = []
    /// Sort order of the list (controlled by the Table header). Default: newest additions first.
    var sortOrder: [KeyPathComparator<Torrent>] = [
        KeyPathComparator(\.addedDateSortKey, order: .reverse)
    ] {
        didSet { recomputeDisplayed() }
    }

    /// Global UI zoom (like a terminal's zoom). Persistent.
    var uiScale: Double = 1.0 {
        didSet { UserDefaults.standard.set(uiScale, forKey: Self.uiScaleKey) }
    }
    private static let uiScaleKey = "uiScale"
    private static let scaleRange = 0.8...2.5

    func zoomIn() { uiScale = min(Self.scaleRange.upperBound, (uiScale + 0.1).rounded(toPlaces: 1)) }
    func zoomOut() { uiScale = max(Self.scaleRange.lowerBound, (uiScale - 0.1).rounded(toPlaces: 1)) }
    func zoomReset() { uiScale = 1.0 }

    /// Whether the Dock icon is visible. If `false`, the app lives only in the menu bar (accessory mode),
    /// with no Dock icon and no app menu bar of its own. Toggleable from the menu bar icon. Persistent.
    /// The launch-time policy is set by `AppDelegate` from the same key.
    var showDockIcon: Bool = true {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: Self.showDockIconKey)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
            // When re-enabling, restore focus so the Dock icon becomes active immediately.
            if showDockIcon { NSApp.activate(ignoringOtherApps: true) }
        }
    }
    static let showDockIconKey = "showDockIcon"

    private var client: RPCClient?
    private var pollingTask: Task<Void, Never>?

    /// Torrent IDs already known to be in the "download finished" state — we notify for
    /// newly finished ones. The `completedSeeded` flag indicates that the first (post-connect)
    /// load has already happened, so existing finished torrents do not generate noise at startup.
    private var completedIDs: Set<Int> = []
    private var completedSeeded = false

    /// Egy sebesség-minta a grafikonhoz (bájt/mp).
    struct SpeedSample: Sendable { let down: Int; let up: Int }
    /// A le/fel sebesség utolsó mintái (a sidebar mini-grafikonhoz és a Statisztika panelhez).
    private(set) var speedHistory: [SpeedSample] = []
    private static let speedHistoryLimit = 120

    private func appendSpeedSample(down: Int, up: Int) {
        speedHistory.append(SpeedSample(down: down, up: up))
        if speedHistory.count > Self.speedHistoryLimit {
            speedHistory.removeFirst(speedHistory.count - Self.speedHistoryLimit)
        }
    }

    /// Összesített le/feltöltés a jelenlegi torrentekre (bájt).
    var totalDownloaded: Int { torrents.reduce(0) { $0 + ($1.downloadedEver ?? 0) } }
    var totalUploaded: Int { torrents.reduce(0) { $0 + ($1.uploadedEver ?? 0) } }
    var activeTorrentCount: Int { torrents.reduce(0) { $0 + ($1.isActive ? 1 : 0) } }

    init() {
        if let saved = UserDefaults.standard.object(forKey: Self.uiScaleKey) as? Double {
            self.uiScale = Self.scaleRange.clamped(saved)
        }
        if let saved = UserDefaults.standard.object(forKey: Self.showDockIconKey) as? Bool {
            self.showDockIcon = saved   // didSet does not run in init → AppDelegate sets the policy
        }
        let loaded = ServerStore.load()
        self.servers = loaded
        // The most recently used server (if it still exists), otherwise the first one.
        if let saved = UserDefaults.standard.string(forKey: Self.selectedServerKey),
           let uuid = UUID(uuidString: saved), loaded.contains(where: { $0.id == uuid }) {
            self.selectedServerID = uuid
        } else {
            self.selectedServerID = loaded.first?.id
        }
    }

    private func persistSelectedServer() {
        if let id = selectedServerID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.selectedServerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedServerKey)
        }
    }

    /// Automatic connect at launch to the most recently used server (once, if there is no client yet).
    func autoConnectIfNeeded() {
        guard client == nil, let server = selectedServer else { return }
        connect(to: server)
    }

    var selectedServer: ServerConfig? {
        guard let selectedServerID else { return nil }
        return servers.first { $0.id == selectedServerID }
    }

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    // MARK: - Filtered list

    /// Recomputes `displayedTorrents` for the current filter/search/sort.
    /// Sorting goes through the fast, typed `TorrentSort.apply` (not `sorted(using:)`).
    private func recomputeDisplayed() {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = torrents.filter { torrent in
            guard filter.matches(torrent) else { return false }
            guard !query.isEmpty else { return true }
            return torrent.displayName.lowercased().contains(query)
        }
        displayedTorrents = TorrentSort.apply(filtered, sortOrder)
    }

    /// Computes the per-filter counts once (when torrents change), so the sidebar
    /// does not walk the list for every filter on every redraw.
    private func recomputeCounts() {
        var counts: [TorrentFilter: Int] = [:]
        for f in TorrentFilter.allCases {
            counts[f] = torrents.reduce(0) { $0 + (f.matches($1) ? 1 : 0) }
        }
        filterCounts = counts
    }

    /// Number of peers (clients) currently connected across all torrents — relative to the
    /// global peer limit it shows how "full" the connection budget is.
    var totalConnectedPeers: Int {
        torrents.reduce(0) { $0 + $1.connectedPeers }
    }

    /// The selected torrent (if exactly one is selected).
    var singleSelectedTorrent: Torrent? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return torrents.first { $0.id == id }
    }

    func count(for filter: TorrentFilter) -> Int {
        filterCounts[filter] ?? 0
    }

    // MARK: - Connection

    func connect(to server: ServerConfig) {
        selectedServerID = server.id
        stopPolling()
        connection = .connecting
        torrents = []
        completedIDs = []
        completedSeeded = false   // on a new server, do not notify about already-finished torrents
        speedHistory = []
        client = RPCClient(config: server)
        startPolling(interval: server.refreshInterval)
    }

    func disconnect() {
        stopPolling()
        client = nil
        connection = .disconnected
        torrents = []
        sessionInfo = nil
        sessionStats = nil
        freeSpace = nil
        speedHistory = []
    }

    private func startPolling(interval: Double) {
        pollingTask = Task { [weak self] in
            guard let self else { return }
            // First pass: session info too.
            await self.loadSessionInfo()
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(max(1, interval)))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        guard let client else { return }
        do {
            async let torrentsResult = client.torrentGet()
            async let statsResult = client.sessionStats()
            let (fetched, stats) = try await (torrentsResult, statsResult)
            notifyNewlyFinished(fetched)
            self.torrents = fetched   // sorting is done by the displayedTorrents cache (per sortOrder)
            self.sessionStats = stats
            appendSpeedSample(down: stats.downloadSpeed ?? 0, up: stats.uploadSpeed ?? 0)
            self.connection = .connected
            await self.refreshDetail()
            await self.loadFreeSpace()
        } catch {
            self.connection = .failed((error as? RPCError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func loadSessionInfo() async {
        guard let client else { return }
        sessionInfo = try? await client.sessionGet()
    }

    /// Sends notifications for torrents that just entered the "download finished" state.
    /// On the first (post-connect) pass it only builds the finished set, without notifying.
    private func notifyNewlyFinished(_ fetched: [Torrent]) {
        let done = Set(fetched.filter { $0.progress >= 1.0 }.map(\.id))
        if completedSeeded {
            for id in done.subtracting(completedIDs) {
                if let t = fetched.first(where: { $0.id == id }) {
                    Notifier.torrentFinished(name: t.displayName)
                }
            }
        }
        completedIDs = done
        completedSeeded = true
    }

    // MARK: - Alternative speed (turtle)

    /// Whether the alternative ("turtle") speed limit is enabled.
    var isAltSpeedOn: Bool { sessionInfo?.altSpeedEnabled ?? false }

    /// Toggles the alternative speed limit (with an optimistic local update).
    func toggleAltSpeed() {
        let newValue = !isAltSpeedOn
        editSession(\.altSpeedEnabled, to: newValue) { $0.altSpeedEnabled = newValue }
    }

    /// Fetches the free space available on the download directory (if the directory is known).
    private func loadFreeSpace() async {
        guard let client, let dir = sessionInfo?.downloadDir, !dir.isEmpty else { return }
        freeSpace = try? await client.freeSpace(path: dir)
    }

    /// Fetches extended fields for the selected torrent (if exactly one is selected).
    func refreshDetail() async {
        guard let client, let id = singleSelectedTorrent?.id else {
            detailTorrent = nil
            return
        }
        if let detail = try? await client.torrentGet(fields: TorrentFields.detail, ids: .ids([.id(id)])).first {
            detailTorrent = detail
        }
    }

    // MARK: - Actions

    private var selectionIDs: RPCIds {
        .ids(selection.map { RPCIdentifier.id($0) })
    }

    func start(ids: RPCIds? = nil) async {
        await perform { try await $0.torrentStart(ids: ids ?? self.selectionIDs) }
    }

    func stop(ids: RPCIds? = nil) async {
        await perform { try await $0.torrentStop(ids: ids ?? self.selectionIDs) }
    }

    func remove(ids: RPCIds? = nil, deleteData: Bool) async {
        await perform { try await $0.torrentRemove(ids: ids ?? self.selectionIDs, deleteLocalData: deleteData) }
    }

    /// Re-check the selected torrents' local data against the hashes.
    func verify(ids: RPCIds? = nil) async {
        await perform { try await $0.torrentVerify(ids: ids ?? self.selectionIDs) }
    }

    /// Ask the trackers for more peers now (reannounce).
    func reannounce(ids: RPCIds? = nil) async {
        await perform { try await $0.torrentReannounce(ids: ids ?? self.selectionIDs) }
    }

    func add(filename: String, paused: Bool = false) async {
        await perform { _ = try await $0.torrentAdd(filename: filename, paused: paused) }
    }

    func add(metainfoBase64: String, paused: Bool = false) async {
        await perform { _ = try await $0.torrentAdd(metainfoBase64: metainfoBase64, paused: paused) }
    }

    /// Adds a `.torrent` file from a URL: security-scoped read + base64 + torrent-add.
    /// Shared path for the Add dialog and drag & drop.
    func addTorrentFile(_ url: URL, paused: Bool = false) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        await add(metainfoBase64: data.base64EncodedString(), paused: paused)
    }

    func applyTorrentSet(_ args: TorrentSetArgs) async {
        await perform { try await $0.torrentSet(args) }
    }

    /// Changes a global session setting, then reloads the current state.
    /// (`perform`'s `refresh()` does not load `sessionInfo`, hence the separate `loadSessionInfo` here.)
    func applySessionSet(_ args: SessionSetArgs) async {
        guard let client else { return }
        do {
            try await client.sessionSet(args)
            await loadSessionInfo()
        } catch {
            connection = .failed((error as? RPCError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Optimistic, immediate edit: updates the local `sessionInfo` field RIGHT AWAY (so the
    /// control reacts instantly without waiting for the server's response), then sends the
    /// `session-set` in the background and reloads the authoritative state. If the server
    /// rejects it, the reload restores the previous value.
    func editSession<V>(_ keyPath: WritableKeyPath<SessionInfo, V?>, to value: V,
                        apply: (inout SessionSetArgs) -> Void) {
        sessionInfo?[keyPath: keyPath] = value
        var args = SessionSetArgs()
        apply(&args)
        Task { await applySessionSet(args) }
    }

    /// Runs an action, then refreshes immediately.
    private func perform(_ action: (RPCClient) async throws -> Void) async {
        guard let client else { return }
        do {
            try await action(client)
            await refresh()
        } catch {
            connection = .failed((error as? RPCError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Server management

    func addOrUpdate(server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        ServerStore.save(servers)
    }

    func deleteServer(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        Keychain.delete(for: server.id)
        ServerStore.save(servers)
        if selectedServerID == server.id {
            disconnect()
            selectedServerID = servers.first?.id
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (self * m).rounded() / m
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
