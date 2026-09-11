import SwiftUI
import TransmissionKit

/// Sheet for `torrent-set-location`: asks for the target directory and whether the
/// daemon should physically move the files.
///
/// The view is deliberately model-free — it reports the result through `onSubmit`,
/// so it can be presented for any set of torrents.
struct MoveTorrentView: View {
    let torrents: [Torrent]
    let onSubmit: (_ location: String, _ move: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var location: String
    @State private var moveData = true
    @FocusState private var locationFocused: Bool

    init(torrents: [Torrent], onSubmit: @escaping (_ location: String, _ move: Bool) -> Void) {
        self.torrents = torrents
        self.onSubmit = onSubmit
        // Prefill only when EVERY target reports a directory and they all agree; a single
        // known directory among several torrents must not stand in for the others.
        let dirs = Set(torrents.compactMap(\.downloadDir))
        let allKnown = torrents.allSatisfy { $0.downloadDir != nil }
        _location = State(initialValue: allKnown && dirs.count == 1 ? (dirs.first ?? "") : "")
    }

    private var sanitized: String? { TorrentRowMenu.sanitizedLocation(location) }

    private var subtitle: String {
        torrents.count == 1
            ? torrents[0].displayName
            : "\(torrents.count) " + loc("kijelölt torrent")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("Torrent áthelyezése")).font(.title2.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                Text(loc("Célmappa a szerveren (abszolút útvonal)")).font(.callout).foregroundStyle(.secondary)
                TextField("/mnt/data/…", text: $location)
                    .textFieldStyle(.roundedBorder)
                    .focused($locationFocused)
            }

            Toggle(loc("Fájlok átmozgatása"), isOn: $moveData)
            Text(moveData
                 ? loc("A daemon átmozgatja a fájlokat az új helyre.")
                 : loc("Csak a nyilvántartott hely változik — a fájloknak már ott kell lenniük."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                Button(loc("Mégse")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(loc("Áthelyezés")) {
                    guard let sanitized else { return }
                    onSubmit(sanitized, moveData)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sanitized == nil)
            }
        }
        .padding(20)
        .frame(width: 480, height: 280)
        .onAppear { locationFocused = true }
    }
}
