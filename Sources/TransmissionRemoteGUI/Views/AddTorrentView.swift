import SwiftUI
import UniformTypeIdentifiers
import TransmissionKit

struct AddTorrentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var magnet = ""
    @State private var paused = false
    @State private var fileImporter = false
    @State private var torrentFile: URL?
    @State private var isAdding = false
    /// Daemon-side destination for this torrent only; prefilled with the daemon's default.
    @State private var downloadDir = ""
    @State private var selectedLabels: Set<String> = []
    @State private var newLabel = ""

    init(incoming: IncomingTorrent? = nil) {
        switch incoming {
        case .file(let url): _torrentFile = State(initialValue: url)
        case .link(let value): _magnet = State(initialValue: value)
        case nil: break
        }
    }

    /// The field may be empty (= daemon default), otherwise it must be an absolute daemon path.
    private var downloadDirIsValid: Bool {
        let trimmed = downloadDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || TorrentRowMenu.sanitizedLocation(trimmed) != nil
    }

    private var currentDirIsFavorite: Bool { model.downloadDirs.isFavorite(downloadDir) }
    private var canFavoriteCurrentDir: Bool {
        TorrentRowMenu.sanitizedLocation(downloadDir) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc("Torrent hozzáadása")).font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                if let torrentFile {
                    Text(torrentFile.lastPathComponent)
                        .lineLimit(2)
                        .accessibilityIdentifier("add.file")
                    Button(loc("Magnet link vagy URL")) { self.torrentFile = nil }
                } else {
                    Text(loc("Magnet link vagy URL")).font(.callout).foregroundStyle(.secondary)
                    TextField("magnet:?xt=… vagy https://…", text: $magnet, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("add.magnet")
                }
            }

            downloadDirSection

            if model.labelsSupported { labelsSection }

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
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled((torrentFile == nil && magnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                          || !downloadDirIsValid || !model.isConnected)
                .accessibilityIdentifier("add.submit")
            }
        }
        .disabled(isAdding)
        .interactiveDismissDisabled(isAdding)
        .padding(20)
        .frame(width: 520, height: model.labelsSupported ? 440 : 350)
        .fileImporter(
            isPresented: $fileImporter,
            allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data]
        ) { result in
            if case .success(let url) = result {
                torrentFile = url
            }
        }
        .onAppear { prefillDownloadDir() }
        // Session info may arrive after the sheet opened: fill in the default if still empty.
        .onChange(of: model.defaultDownloadDir) { prefillDownloadDir() }
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("Címkék")).font(.callout).foregroundStyle(.secondary)
            Menu {
                Button(loc("Nincs címke"), systemImage: selectedLabels.isEmpty ? "checkmark" : "") {
                    selectedLabels.removeAll()
                }
                if !model.labelGroups.isEmpty {
                    Divider()
                    ForEach(model.labelGroups, id: \.value) { entry in
                        Button {
                            toggleLabel(entry.value)
                        } label: {
                            Label(entry.value, systemImage: selectedLabels.contains(entry.value) ? "checkmark" : "tag")
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedLabels.isEmpty ? loc("Nincs címke") : selectedLabels.sorted().joined(separator: ", "))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            .accessibilityIdentifier("add.labels")
            HStack(spacing: 6) {
                TextField(loc("Új címke"), text: $newLabel)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("add.label.new")
                Button(loc("Létrehozás"), action: createLabel)
                    .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func toggleLabel(_ label: String) {
        if selectedLabels.contains(label) { selectedLabels.remove(label) }
        else { selectedLabels.insert(label) }
    }

    private func createLabel() {
        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        selectedLabels.insert(label)
        newLabel = ""
    }

    // MARK: - Download directory

    private var downloadDirSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("Célmappa a szerveren (abszolút útvonal)")).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(model.defaultDownloadDir ?? "/mnt/data/…", text: $downloadDir)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("add.downloadDir")
                    .accessibilityLabel(loc("Célmappa a szerveren (abszolút útvonal)"))
                Button {
                    if currentDirIsFavorite {
                        model.removeFavoriteDownloadDir(downloadDir)
                    } else {
                        model.addFavoriteDownloadDir(downloadDir)
                    }
                } label: {
                    Image(systemName: currentDirIsFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .disabled(!canFavoriteCurrentDir)
                .help(currentDirIsFavorite ? loc("Eltávolítás a kedvencek közül") : loc("Hozzáadás a kedvencekhez"))
                .accessibilityLabel(currentDirIsFavorite ? loc("Eltávolítás a kedvencek közül") : loc("Hozzáadás a kedvencekhez"))
                .accessibilityIdentifier("add.downloadDir.favorite")
                downloadDirMenu
            }
            let mapped = DownloadDirectories.mappedDestinations(model.selectedServer?.pathMappings ?? [])
            if !mapped.isEmpty {
                Picker(loc("Mentés ide:"), selection: $downloadDir) {
                    if !mapped.contains(downloadDir) {
                        Text(downloadDir.isEmpty ? loc("Alapértelmezett mappa") : downloadDir).tag(downloadDir)
                    }
                    ForEach(mapped, id: \.self) { dir in
                        Text(dir).tag(dir)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("add.downloadDir.mappings")
            }
            if downloadDirIsValid {
                Text(loc("Csak ennél a torrentnél — a szerver alapértelmezett mappája nem változik."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(loc("Abszolút útvonalat adj meg, vagy hagyd üresen az alapértelmezett mappához."))
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("add.downloadDir.error")
            }
        }
    }

    private var downloadDirMenu: some View {
        let dirs = model.downloadDirs
        return Menu {
            if let defaultDir = model.defaultDownloadDir {
                Button(loc("Alapértelmezett mappa") + ": " + defaultDir) { downloadDir = defaultDir }
                    .accessibilityIdentifier("add.downloadDir.default")
            }
            if !dirs.favorites.isEmpty {
                Section(loc("Kedvencek")) {
                    ForEach(dirs.favorites, id: \.self) { dir in
                        Button(dir) { downloadDir = dir }
                    }
                }
            }
            if !dirs.recent.isEmpty {
                Section(loc("Legutóbb használt")) {
                    ForEach(dirs.recent, id: \.self) { dir in
                        Button(dir) { downloadDir = dir }
                    }
                }
            }
            Divider()
            if currentDirIsFavorite {
                Button(loc("Eltávolítás a kedvencek közül")) { model.removeFavoriteDownloadDir(downloadDir) }
            } else {
                Button(loc("Hozzáadás a kedvencekhez")) { model.addFavoriteDownloadDir(downloadDir) }
                    .disabled(!canFavoriteCurrentDir)
            }
            if !dirs.favorites.isEmpty {
                Menu(loc("Kedvenc eltávolítása")) {
                    ForEach(dirs.favorites, id: \.self) { dir in
                        Button(dir) { model.removeFavoriteDownloadDir(dir) }
                    }
                }
            }
            Button(loc("Előzmények törlése")) { model.clearRecentDownloadDirs() }
                .disabled(dirs.recent.isEmpty)
        } label: {
            Image(systemName: "folder.badge.gearshape")
        }
        .menuIndicator(.visible)
        .fixedSize()
        .help(loc("Kedvenc és legutóbbi mappák"))
        .accessibilityLabel(loc("Kedvenc és legutóbbi mappák"))
        .accessibilityIdentifier("add.downloadDir.menu")
    }

    private func prefillDownloadDir() {
        if downloadDir.isEmpty, let dir = model.defaultDownloadDir { downloadDir = dir }
    }

    /// What to send with `torrent-add` (nil = let the daemon use its default) and how to record
    /// it in this server's history once the add succeeded. The server is captured now, so a
    /// server switch while the request runs cannot file the path under the wrong server.
    private func resolvedDownloadDir() -> (dir: String?, record: @MainActor () -> Void) {
        let dir = DownloadDirectories.effectiveDownloadDir(downloadDir, daemonDefault: model.defaultDownloadDir)
        let serverID = model.selectedServerID
        return (dir, {
            if let dir, let serverID { model.recordUsedDownloadDir(dir, serverID: serverID) }
        })
    }

    private func submit() {
        guard !isAdding, model.isConnected, downloadDirIsValid else { return }
        let value = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard torrentFile != nil || !value.isEmpty else { return }
        let target = resolvedDownloadDir()
        isAdding = true
        Task {
            let result: TorrentAddResult?
            if let torrentFile {
                result = await model.addTorrentFile(torrentFile, paused: paused, downloadDir: target.dir)
            } else {
                result = await model.add(filename: value, paused: paused, downloadDir: target.dir)
            }
            isAdding = false
            if let result {
                target.record()
                // Duplicate responses never overwrite the existing torrent's labels.
                if let id = result.added?.id, !selectedLabels.isEmpty {
                    await model.setLabels(selectedLabels.sorted(), ids: .ids([.id(id)]))
                }
                dismiss()
            }
        }
    }
}
