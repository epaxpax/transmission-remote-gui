import SwiftUI
import UniformTypeIdentifiers
import TransmissionKit

struct AddTorrentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var magnet = ""
    @State private var paused = false
    @State private var fileImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("Torrent hozzáadása")).font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text(loc("Magnet link vagy URL")).font(.callout).foregroundStyle(.secondary)
                TextField("magnet:?xt=… vagy https://…", text: $magnet, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button {
                    fileImporter = true
                } label: {
                    Label(loc(".torrent fájl választása"), systemImage: "doc.badge.plus")
                }
                Spacer()
                Toggle(loc("Leállítva add hozzá"), isOn: $paused)
            }

            Spacer()

            HStack {
                Spacer()
                Button(loc("Mégse")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(loc("Hozzáadás")) {
                    let value = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    Task {
                        await model.add(filename: value, paused: paused)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(magnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 260)
        .fileImporter(
            isPresented: $fileImporter,
            allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data]
        ) { result in
            if case .success(let url) = result {
                addTorrentFile(url)
            }
        }
    }

    private func addTorrentFile(_ url: URL) {
        Task {
            await model.addTorrentFile(url, paused: paused)
            dismiss()
        }
    }
}
