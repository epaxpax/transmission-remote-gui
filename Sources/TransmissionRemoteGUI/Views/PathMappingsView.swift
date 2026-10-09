import SwiftUI
import AppKit
import TransmissionKit

/// Draft rows have stable IDs while their path text is being edited.
struct PathMappingDraft: Identifiable {
    let id = UUID()
    var remotePath = ""
    var localPath = ""
    var mapping: PathMapping { PathMapping(remotePath: remotePath, localPath: localPath) }
    var isEmpty: Bool { remotePath.isEmpty && localPath.isEmpty }

    init(_ mapping: PathMapping = PathMapping(remotePath: "", localPath: "")) {
        remotePath = mapping.remotePath
        localPath = mapping.localPath
    }
}

struct PathMappingsView: View {
    @Binding var rows: [PathMappingDraft]
    @State private var showImport = false
    @State private var importText = ""
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("Csak a helyi Finder-megjelenítést érinti. A megosztásokat előbb kézzel csatold."))
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(loc("Távoli mappa")).frame(width: 88, alignment: .leading)
                                TextField(loc("Távoli mappa"), text: $row.remotePath)
                                    .accessibilityIdentifier("mapping.remote." + row.id.uuidString)
                                Button {
                                    rows.removeAll { $0.id == row.id }
                                } label: { Image(systemName: "minus.circle") }
                                    .help(loc("Hozzárendelés eltávolítása"))
                                    .accessibilityLabel(loc("Hozzárendelés eltávolítása"))
                            }
                            HStack {
                                Text(loc("Helyi mappa")).frame(width: 88, alignment: .leading)
                                TextField(loc("Helyi mappa"), text: $row.localPath)
                                    .accessibilityIdentifier("mapping.local." + row.id.uuidString)
                                Button(loc("Tallózás…")) { chooseFolder(for: row.id) }
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        Divider()
                    }
                }
            }
            HStack {
                Button(loc("Új hozzárendelés")) { rows.append(PathMappingDraft()) }
                Button(loc("Beillesztés…")) {
                    importText = NSPasteboard.general.string(forType: .string) ?? ""
                    importError = nil
                    showImport = true
                }
            }
            if let error = validationError {
                Text(error).foregroundStyle(.red).font(.callout)
            }
        }
        .padding(12)
        .sheet(isPresented: $showImport) {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc("Távoli útvonal=helyi útvonal, soronként egy."))
                TextEditor(text: $importText).font(.body.monospaced())
                    .accessibilityIdentifier("mapping.import")
                    .frame(minHeight: 180)
                if let importError { Text(importError).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button(loc("Mégse")) { showImport = false }.keyboardShortcut(.cancelAction)
                    Button(loc("Importálás")) { importMappings() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(width: 520, height: 300)
        }
    }

    private var validationError: String? {
        do { _ = try PathMapping.validated(rows.filter { !$0.isEmpty }.map(\.mapping)); return nil }
        catch { return locPathMappingError(error) }
    }

    private func importMappings() {
        do {
            let imported = try PathMapping.parse(importText)
            let combined = try PathMapping.validated(rows.filter { !$0.isEmpty }.map(\.mapping) + imported)
            rows = combined.map(PathMappingDraft.init)
            showImport = false
        } catch { importError = locPathMappingError(error) }
    }

    private func chooseFolder(for id: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let index = rows.firstIndex(where: { $0.id == id }) else { return }
            rows[index].localPath = url.path
        }
    }
}
