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
    /// Sidebar tracker / folder / label groups with counts — populated when torrents change.
    private(set) var trackerGroups: [SidebarGroups.Entry] = []
    private(set) var folderGroups: [SidebarGroups.Entry] = []
    private(set) var labelGroups: [SidebarGroups.Entry] = []
    /// Trackers per torrent id, fetched apart from the list poll (see `mergeTrackers`).
    private var trackersByID: [Int: [Tracker]] = [:]
    private var trackersFetchedAt: Date?
    /// Trackers rarely change, so the full tracker fetch runs this seldom; new torrents
    /// get theirs on the very next poll.
    private static let trackerRefreshInterval: TimeInterval = 300
    /// The selected torrent with extended fields (files/peers/trackers) — for the detail view.
    private(set) var detailTorrent: Torrent?
    private(set) var sessionInfo: SessionInfo?
    private(set) var sessionStats: SessionStats?
    /// Free disk space (bytes) on the download directory — on the daemon's machine.
    private(set) var freeSpace: Int?

    // UI state
    var filter: TorrentFilter = .all { didSet { recomputeDisplayed() } }
    var searchText: String = "" { didSet { recomputeDisplayed() } }
    /// Optional label (category) filter, chosen in the sidebar. nil = no label filter.
    var labelFilter: String? { didSet { recomputeDisplayed() } }
    /// Optional tracker-host filter (e.g. "tracker.example.org"). nil = no tracker filter.
    var trackerFilter: String? { didSet { recomputeDisplayed() } }
    /// Optional download-folder filter (a `SidebarGroups.folderKey`). nil = no folder filter.
    var folderFilter: String? { didSet { recomputeDisplayed() } }
    var selection: Set<Int> = []

    /// Last failed action's message, shown as an alert and cleared when dismissed.
    /// Separate from `connection`, which describes the link to the server.
    var actionError: String?

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

    /// RSS auto-downloader: feeds + rules + dedup (persisted).
    let rss = RSSStore()
    private var rssPollTask: Task<Void, Never>?

    /// Rule engine state. Owned here so every view reaches the same instance.
    let ruleStore = RuleStore()
    /// While set, `runRulesInBackground` returns immediately. Set after a pass throws,
    /// cleared when it elapses or when connecting to a server. Not persisted: a restart
    /// is exactly the moment a user would expect another attempt.
    private var rulesSkipUntil: Date?

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

    /// Strips the parenthetical build suffix off a raw daemon version string, e.g.
    /// `"4.1.1 (32ba7be3)"` → `"4.1.1"`. Shared by `supportsSequential` (which needs the
    /// numeric major/minor) and `daemonVersion` (which just displays the result), so the
    /// parsing rule lives in exactly one place.
    private func versionNumberPrefix(_ raw: String) -> String {
        raw.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
    }

    /// Sequential ("streaming") download needs Transmission 4.1+. Parses the daemon
    /// version (e.g. "4.1.1 (hash)") → true when major.minor ≥ 4.1.
    var supportsSequential: Bool {
        guard let v = sessionInfo?.version else { return false }
        let parts = versionNumberPrefix(v)
            .split(separator: ".")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2 else { return false }
        return parts[0] > 4 || (parts[0] == 4 && parts[1] >= 1)
    }

    /// The daemon's version as reported, for messages that gate a feature. Naming the
    /// current version matters: the user needs to know what they have, not only what
    /// the feature needs.
    var daemonVersion: String {
        guard let v = sessionInfo?.version else { return loc("ismeretlen") }
        let stripped = versionNumberPrefix(v)
        return stripped.isEmpty ? loc("ismeretlen") : stripped
    }

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
            if let label = labelFilter, !(torrent.labels ?? []).contains(label) { return false }
            if let tracker = trackerFilter, !torrent.trackerHosts.contains(tracker) { return false }
            if let folder = folderFilter, !SidebarGroups.matchesFolder(torrent, folder) { return false }
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
        trackerGroups = SidebarGroups.trackers(torrents)
        folderGroups = SidebarGroups.folders(torrents)
        labelGroups = SidebarGroups.labels(torrents)
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
        if server.id != incomingServerID { _ = incoming.drain() }
        if server.id != selectedServerID {
            labelFilter = nil; trackerFilter = nil; folderFilter = nil   // values of the old server
        }
        selectedServerID = server.id
        stopPolling()
        connection = .connecting
        torrents = []
        completedIDs = []
        completedSeeded = false   // on a new server, do not notify about already-finished torrents
        speedHistory = []
        trackersByID = [:]        // another server's torrent ids mean other torrents
        trackersFetchedAt = nil
        rulesSkipUntil = nil      // a different (or repaired) server deserves a fresh attempt
        client = RPCClient(config: server, session: server.makeSession())
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
                await self.runRulesInBackground()
                try? await Task.sleep(for: .seconds(max(1, interval)))
            }
        }
        // RSS auto-downloader: check feeds every 15 minutes while connected.
        rssPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.rssPoll()
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        rssPollTask?.cancel()
        rssPollTask = nil
    }

    /// One RSS pass: fetch each enabled feed, add items that match a rule and haven't been seen.
    func rssPoll() async {
        guard rss.enabled, client != nil else { return }
        for feed in rss.feeds where feed.enabled {
            guard let url = URL(string: feed.url),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            for item in RSSParser.parse(data)
            where !rss.isSeen(item.guid) && rss.titleMatchesAnyRule(item.title) {
                await add(filename: item.link)     // magnet or .torrent URL
                rss.markSeen(item.guid)            // mark regardless, so we don't retry every pass
            }
        }
    }

    func refresh() async {
        guard let client else { return }
        do {
            async let torrentsResult = client.torrentGet()
            async let statsResult = client.sessionStats()
            let (listed, stats) = try await (torrentsResult, statsResult)
            let fetched = await mergeTrackers(into: listed, client: client)
            notifyNewlyFinished(fetched)
            self.torrents = fetched   // sorting is done by the displayedTorrents cache (per sortOrder)
            self.sessionStats = stats
            appendSpeedSample(down: stats.downloadSpeed ?? 0, up: stats.uploadSpeed ?? 0)
            self.connection = .connected
            await self.addPendingIncoming()
            await self.refreshDetail()
            await self.loadFreeSpace()
        } catch {
            self.connection = .failed(locError(error))
        }
    }

    /// Copies each torrent's trackers onto the list torrents. The list poll leaves them out
    /// (`TorrentFields.trackers`), so they come from a separate `id + trackers` query: only
    /// for ids not seen yet, plus a full refresh every `trackerRefreshInterval`. A failed
    /// query is simply retried on the next poll — the filter is never worth a failed refresh.
    private func mergeTrackers(into listed: [Torrent], client: RPCClient) async -> [Torrent] {
        let stale = trackersFetchedAt.map { Date().timeIntervalSince($0) > Self.trackerRefreshInterval } ?? true
        let missing = stale ? [] : listed.map(\.id).filter { trackersByID[$0] == nil }
        if stale || !missing.isEmpty,
           let rows = try? await client.torrentGet(fields: TorrentFields.trackers,
                                                   ids: stale ? .all : .ids(missing.map { .id($0) })) {
            if stale { trackersByID = [:]; trackersFetchedAt = Date() }
            for row in rows { trackersByID[row.id] = row.trackers ?? [] }
        }
        let present = Set(listed.map(\.id))
        if trackersByID.count > present.count { trackersByID = trackersByID.filter { present.contains($0.key) } }
        return listed.map { var t = $0; t.trackers = trackersByID[t.id]; return t }
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

    // MARK: - Szabályok

    /// Plans without applying anything — the dry run behind the editor preview and the
    /// manual "run now".
    ///
    /// `failed` is a dedicated signal, distinct from `plan.isEmpty`: an empty plan alone
    /// cannot tell "nothing matched" apart from "could not even ask" (no connection, or
    /// the fetch threw). Callers that show an empty-plan message — `RulePreviewView` via
    /// its `couldNotDetermine` parameter — should read `failed`, not touch `actionError`
    /// themselves: doing so risks dismissing an unrelated alert `TorrentListView` has
    /// bound to the same shared property. `actionError` is still set (and surfaces its
    /// usual alert) for a genuine RPC failure in the `catch` — just not for "no client".
    func previewRules(_ rules: [TorrentRule], force: Bool) async -> (plan: [PlannedChange], failed: Bool) {
        guard let client else { return ([], true) }
        let classified = ruleStore.classifiedHashes
        // `force` re-plans everything, including already-classified torrents, so the id
        // list must stay unfiltered in that case. When it's false, the engine discards
        // already-classified torrents anyway (a hash-less torrent is never considered
        // classified, so it's always kept) — filter here so a multi-thousand torrent
        // library doesn't send every id through a full `ruleInputs` fetch for nothing.
        let ids = force ? torrents.map(\.id) : torrents
            .filter { torrent in
                guard let hash = torrent.hashString else { return true }
                return !classified.contains(hash)
            }
            .map(\.id)
        do {
            let plan = try await RuleRunner.plan(client: client, rules: rules, ids: ids,
                                                 alreadyClassified: ruleStore.classifiedHashes,
                                                 force: force)
            return (plan, false)
        } catch {
            actionError = message(for: error)
            return ([], true)
        }
    }

    /// Applies a plan the user has seen and confirmed. Surfaces failures in an alert,
    /// because the user is standing at the button.
    func applyPlan(_ plan: [PlannedChange]) async {
        guard let client else { return }
        let result = await RuleRunner.apply(plan, client: client)
        ruleStore.markClassified(Set(result.applied))
        ruleStore.lastRun = RunSummary(date: Date(), applied: result.applied.count,
                                       failed: result.failures.count, messages: result.failures)
        if !result.failures.isEmpty {
            actionError = result.failures.joined(separator: "\n")
        }
        await refresh()
    }

    /// The background pass: plans and applies for torrents not seen before. Never
    /// raises an alert — failures go to `ruleStore.lastRun`, visible in the Rules window.
    func runRulesInBackground() async {
        // Skip while the connection is down: `torrents` is stale, a `torrentGet` would
        // just fail, and — critically — a failed pass must not overwrite `lastRun`
        // (the only feedback surface this feature has) with a connection error every
        // 5 seconds, discarding the last real summary.
        guard case .connected = connection, ruleStore.enabled,
              ruleStore.rules.contains(where: \.enabled), let client else { return }
        // Back off after a thrown pass. A `ruleInputs` fetch that keeps timing out on a
        // server that still reads as connected marks nothing, so the whole library would
        // be re-fetched — trackers and all — every poll tick forever, and every failure
        // would overwrite `lastRun`, destroying the last real summary.
        if let until = rulesSkipUntil {
            guard Date() >= until else { return }
            rulesSkipUntil = nil
        }
        let classified = ruleStore.classifiedHashes
        // Bounded slice, not the whole backlog. On the first tick after the master switch
        // goes on nothing is classified, so every torrent is a candidate — and `apply`
        // sends one `torrent-set` (plus an optional `torrent-stop`) per torrent, awaited
        // serially, with this whole method awaited inside the poll loop before its sleep.
        // Uncapped, a seedbox-sized library freezes the list, speed graph and stats for
        // minutes, and quitting mid-pass discards all of it because `markClassified` only
        // runs at the end. A capped pass converges over several ticks and persists its
        // progress after each one.
        let candidates = Array(torrents.filter { torrent in
            guard let hash = torrent.hashString else { return false }
            return !classified.contains(hash)
        }.prefix(Self.backgroundPassLimit))
        guard !candidates.isEmpty else { return }
        do {
            let plan = try await RuleRunner.plan(client: client, rules: ruleStore.rules,
                                                 ids: candidates.map(\.id),
                                                 alreadyClassified: classified, force: false)
            // A torrent that matches nothing must still count as handled, or every pass
            // would re-query it forever. (A torrent removed from the daemon between this
            // poll's snapshot and the ruleInputs fetch is likewise absent from the plan
            // and gets marked here too — harmless, just a dead hash in a bounded set.)
            let planned = Set(plan.compactMap(\.torrentHash))
            let result = await RuleRunner.apply(plan, client: client)
            var toMark = Set(result.applied)
            for torrent in candidates {
                if let hash = torrent.hashString, !planned.contains(hash) { toMark.insert(hash) }
            }
            ruleStore.markClassified(toMark)
            if result.applied.count + result.failures.count > 0 {
                ruleStore.lastRun = RunSummary(date: Date(), applied: result.applied.count,
                                               failed: result.failures.count, messages: result.failures)
            }
        } catch {
            ruleStore.lastRun = RunSummary(date: Date(), applied: 0, failed: 1,
                                           messages: [message(for: error)])
            rulesSkipUntil = Date().addingTimeInterval(Self.rulesBackoff)
        }
    }

    /// How many unclassified torrents one background pass may handle. See the comment at
    /// the slice in `runRulesInBackground`.
    private static let backgroundPassLimit = 200
    /// How long to stay quiet after a background pass threw. Generous on purpose: the
    /// failure mode this guards against is a daemon that keeps timing out, which will not
    /// recover within a poll interval, and "Futtatás most…" stays available throughout.
    private static let rulesBackoff: TimeInterval = 300

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

    /// Move the given (or selected) torrents' data to `location`.
    /// With `move: false` only the recorded location changes — use it when the files
    /// were already moved by other means.
    func setLocation(_ location: String, move: Bool, ids: RPCIds? = nil) async {
        await perform { try await $0.torrentSetLocation(ids: ids ?? self.selectionIDs, location: location, move: move) }
    }

    /// Rename a single torrent's top-level path, i.e. the name shown in the list.
    func rename(id: Int, from oldName: String, to newName: String) async {
        await perform { try await $0.torrentRenamePath(id: id, path: oldName, name: newName) }
    }

    /// Enable/disable sequential ("streaming") download on the selection (Transmission 4.1+).
    func setSequential(on: Bool, ids: RPCIds? = nil) async {
        await perform {
            var args = TorrentSetArgs(ids: ids ?? self.selectionIDs)
            args.sequentialDownload = on
            try await $0.torrentSet(args)
        }
    }

    /// Set per-torrent speed limits (KB/s) on the given (or selected) torrents.
    func setSpeedLimit(downEnabled: Bool, down: Int, upEnabled: Bool, up: Int, ids: RPCIds? = nil) async {
        await perform {
            var args = TorrentSetArgs(ids: ids ?? self.selectionIDs)
            args.downloadLimited = downEnabled
            args.downloadLimit = down
            args.uploadLimited = upEnabled
            args.uploadLimit = up
            try await $0.torrentSet(args)
        }
    }

    /// Replace the labels (categories/tags) on the given (or selected) torrents.
    func setLabels(_ labels: [String], ids: RPCIds? = nil) async {
        await perform {
            var args = TorrentSetArgs(ids: ids ?? self.selectionIDs)
            args.labels = labels
            try await $0.torrentSet(args)
        }
    }

    func add(filename: String, paused: Bool = false) async {
        await perform { _ = try await $0.torrentAdd(filename: filename, paused: paused) }
    }

    func add(metainfoBase64: String, paused: Bool = false) async {
        await perform { _ = try await $0.torrentAdd(metainfoBase64: metainfoBase64, paused: paused) }
    }

    /// Torrents opened from outside (Finder, browser magnet link) before a connection existed.
    private var incoming = IncomingQueue()
    /// The server the queued torrents were meant for. Switching to another server drops the
    /// queue, so nothing lands on a server the user did not have selected when opening them.
    private var incomingServerID: UUID?

    /// Entry point for Finder "Open" / "Open With" and clicked magnet links. Adds right away
    /// when connected; otherwise queues them and (re)connects to the last server — the queue
    /// is flushed by the first successful poll.
    func openIncoming(_ urls: [URL]) {
        let items = urls.compactMap(IncomingTorrent.classify)
        guard !items.isEmpty else { return }
        if incomingServerID != selectedServerID { _ = incoming.drain() }
        incomingServerID = selectedServerID
        incoming.enqueue(items)
        if isConnected {
            Task { await addPendingIncoming() }
            return
        }
        if connection != .connecting { autoConnectIfNeeded() }
        if selectedServer == nil || client == nil || connection != .connecting {
            // No server, or the last attempt failed: without this the open would look ignored.
            actionError = loc("Nincs kapcsolat a szerverrel — a megnyitott torrentek a csatlakozás után kerülnek fel.")
        }
    }

    private func addPendingIncoming() async {
        guard incomingServerID == selectedServerID else { return }
        for item in incoming.drain() {
            await add(item)
        }
    }

    /// Adds one incoming torrent — shared by Open With, magnet links and drag & drop.
    func add(_ item: IncomingTorrent) async {
        switch item {
        case .file(let url): await addTorrentFile(url)
        case .link(let value): await add(filename: value)
        }
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
            actionError = message(for: error)
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
    ///
    /// A failed action is NOT a lost connection: reporting it through `connection` would
    /// replace the whole list with an error placeholder for the one second until the next
    /// refresh, hiding the message instead of showing it. Genuine connection loss is
    /// detected by `refresh()` itself.
    private func perform(_ action: (RPCClient) async throws -> Void) async {
        guard let client else { return }
        do {
            try await action(client)
            await refresh()
        } catch {
            actionError = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        locError(error)
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
