import SwiftUI
import TransmissionKit

/// Sheet for `torrent-rename-path`: renames a single torrent's top-level path,
/// i.e. the name shown in the list. The RPC takes exactly one torrent per call.
struct RenameTorrentView: View {
    let torrent: Torrent
    let onSubmit: (_ newName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(torrent: Torrent, onSubmit: @escaping (_ newName: String) -> Void) {
        self.torrent = torrent
        self.onSubmit = onSubmit
        _name = State(initialValue: torrent.name ?? "")
    }

    /// `current:` also rejects the unchanged name, so the button stays disabled until
    /// the user actually changes something.
    private var sanitized: String? { TorrentRowMenu.sanitizedName(name, current: torrent.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("Torrent átnevezése")).font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text(loc("Új név")).font(.callout).foregroundStyle(.secondary)
                // Return is already bound to the default action below; a second
                // `.onSubmit` here would fire the rename twice.
                TextField("", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
            }

            Text(loc("A daemon a letöltési mappában is átnevezi a fájlt/mappát. A név nem tartalmazhat „/” karaktert."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                Button(loc("Mégse")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(loc("Átnevezés"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sanitized == nil)
            }
        }
        .padding(20)
        .frame(width: 480, height: 220)
        .onAppear { nameFocused = true }
    }

    private func submit() {
        guard let sanitized else { return }
        onSubmit(sanitized)
        dismiss()
    }
}
