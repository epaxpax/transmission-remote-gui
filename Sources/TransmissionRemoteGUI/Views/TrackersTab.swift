import SwiftUI
import TransmissionKit

struct TrackersTab: View {
    @Environment(AppModel.self) private var model
    let torrent: Torrent
    let serverID: UUID?
    @State private var sortOrder = [KeyPathComparator(\TrackerStat.displayHost)]
    @State private var selection: TrackerStat.ID?
    @State private var showsAdd = false
    @State private var pendingRemoval: String?

    private var trackers: [TrackerStat] { torrent.trackerStats ?? [] }
    private var busy: Bool { model.trackerEditsInFlight.contains(torrent.id) }
    private var selectedURL: String? {
        trackers.first { $0.id == selection }?.announce
    }

    var body: some View {
        VStack(spacing: 0) {
            if trackers.isEmpty {
                Text(loc("Nincs tracker információ")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(trackers.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                    TableColumn(loc("Tracker"), value: \.displayHost) {
                        Text($0.displayHost).lineLimit(1).help($0.announce ?? $0.displayHost)
                    }
                    TableColumn(loc("Állapot"), value: \.resultSortKey) {
                        Text(Localization.shared.trackerResult($0.lastAnnounceResult)).lineLimit(1)
                    }
                    TableColumn(loc("Seedek"), value: \.seederSortKey) { Text(count($0.seederCount)) }.width(60)
                    TableColumn(loc("Leecherek"), value: \.leecherSortKey) { Text(count($0.leecherCount)) }.width(70)
                }
                .accessibilityIdentifier("trackers.table")
            }
            Divider()
            HStack(spacing: 0) {
                Button { showsAdd = true } label: { Image(systemName: "plus") }
                    .help(loc("Tracker hozzáadása"))
                    .accessibilityLabel(loc("Tracker hozzáadása"))
                    .accessibilityIdentifier("trackers.add")
                Button { pendingRemoval = selectedURL } label: { Image(systemName: "minus") }
                    .disabled(selectedURL == nil)
                    .help(loc("Tracker eltávolítása"))
                    .accessibilityLabel(loc("Tracker eltávolítása"))
                    .accessibilityIdentifier("trackers.remove")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
            .disabled(busy || !model.isConnected)
        }
        .onChange(of: trackers) { _, updated in
            if !updated.contains(where: { $0.id == selection }) { selection = nil }
        }
        .sheet(isPresented: $showsAdd) {
            AddTrackerSheet { url in
                try await model.editTracker(.add(url), torrentID: torrent.id, serverID: serverID)
            }
        }
        .alert(loc("Tracker eltávolítása?"), isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { url in
            Button(loc("Mégse"), role: .cancel) {}
                .accessibilityIdentifier("trackers.cancelRemove")
            Button(loc("Eltávolítás"), role: .destructive) {
                Task {
                    do { try await model.editTracker(.remove(url), torrentID: torrent.id, serverID: serverID) }
                    catch { model.actionError = locError(error) }
                }
            }
            .accessibilityIdentifier("trackers.confirmRemove")
        } message: { _ in
            Text(loc("Eltávolítod a kijelölt trackert ebből a torrentből?"))
        }
    }

    private func count(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return "\(value)"
    }
}

private struct AddTrackerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let add: (String) async throws -> Void
    @State private var url = ""
    @State private var submitting = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("Tracker hozzáadása")).font(.headline)
            TextField(loc("Tracker URL"), text: $url)
                .focused($focused)
                .accessibilityIdentifier("trackers.url")
                .onSubmit { submit() }
            Text(loc("Adj meg érvényes http, https vagy udp tracker URL-t."))
                .font(.caption).foregroundStyle(.secondary)
            if let error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trackers.error")
            }
            HStack {
                Spacer()
                Button(loc("Mégse")) { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("trackers.cancel")
                Button(loc("Hozzáad")) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(TrackerEdit.validatedURL(url) == nil)
                    .accessibilityIdentifier("trackers.submit")
            }
        }
        .padding(20).frame(width: 420)
        .disabled(submitting)
        .interactiveDismissDisabled(submitting)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !submitting, let url = TrackerEdit.validatedURL(url) else { return }
        submitting = true
        error = nil
        Task {
            do { try await add(url); dismiss() }
            catch { self.error = locError(error); submitting = false }
        }
    }
}
