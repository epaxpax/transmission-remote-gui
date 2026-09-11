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

    init(torrents: [Torrent], onSubmit: @escaping (_ location: String, _ move: Bool) -> Void) {
        self.torrents = torrents
        self.onSubmit = onSubmit
        // Prefill only when every target currently sits in the same directory.
        let dirs = Set(torrents.compactMap(\.downloadDir))
        _location = State(initialValue: dirs.count == 1 ? (dirs.first ?? "") : "")
    }

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
                Text(loc("Célmappa a szerveren")).font(.callout).foregroundStyle(.secondary)
                TextField("/mnt/data/…", text: $location)
                    .textFieldStyle(.roundedBorder)
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
                    guard let value = TorrentRowMenu.sanitizedLocation(location) else { return }
                    onSubmit(value, moveData)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(TorrentRowMenu.sanitizedLocation(location) == nil)
            }
        }
        .padding(20)
        .frame(width: 480, height: 260)
    }
}
