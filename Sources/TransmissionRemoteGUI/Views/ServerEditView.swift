import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TransmissionKit

struct ServerEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let server: ServerConfig?

    @State private var name = ""
    @State private var host = "127.0.0.1"
    @State private var port = "9091"
    @State private var path = "/transmission/rpc"
    @State private var useHTTPS = false
    @State private var username = ""
    @State private var password = ""
    @State private var refreshInterval = 3.0
    @State private var clientCertPath = ""
    @State private var clientCertPassword = ""
    @State private var showCertImporter = false
    @State private var pathMappings: [PathMappingDraft] = []
    @State private var watchFolderPath = ""

    private var isEditing: Bool { server != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? loc("Szerver szerkesztése") : loc("Új szerver"))
                .font(.title2.bold())
                .padding(.bottom, 12)

            TabView {
                Form {
                    TextField(loc("Név"), text: $name)
                    TextField(loc("Hoszt"), text: $host)
                    TextField("Port", text: $port)
                    TextField(loc("RPC útvonal"), text: $path)
                    Toggle("HTTPS", isOn: $useHTTPS)
                    TextField(loc("Felhasználónév (opcionális)"), text: $username)
                    SecureField(loc("Jelszó (opcionális)"), text: $password)
                    HStack {
                        Text(loc("Frissítés"))
                        Slider(value: $refreshInterval, in: 1...30, step: 1)
                        Text("\(Int(refreshInterval)) \(loc("mp"))").monospacedDigit().frame(width: 48)
                    }
                    Section(loc("Kliens-tanúsítvány (mTLS, opcionális)")) {
                        HStack {
                            TextField(loc(".p12 fájl útvonala"), text: $clientCertPath)
                            Button(loc("Tallózás…")) { showCertImporter = true }
                        }
                        SecureField(loc("Tanúsítvány jelszava"), text: $clientCertPassword)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text(loc("Csatlakozás")) }
                PathMappingsView(rows: $pathMappings)
                    .tabItem { Text(loc("Útvonal-hozzárendelések")) }
                watchFolderTab
                    .tabItem { Text(loc("Figyelt mappa")) }
            }
            .fileImporter(isPresented: $showCertImporter,
                          allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data,
                                                UTType(filenameExtension: "pfx") ?? .data]) { result in
                if case .success(let url) = result { clientCertPath = url.path }
            }

            HStack {
                Spacer()
                Button(loc("Mégse")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? loc("Mentés") : loc("Hozzáadás")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || host.isEmpty || !mappingsAreValid || !watchFolderIsValid || watchFolderInUse)
                    .accessibilityIdentifier("server.save")
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 460, height: 560)
        .onAppear(perform: loadFields)
    }

    private func loadFields() {
        guard let server else { return }
        name = server.name
        host = server.host
        port = String(server.port)
        path = server.path
        useHTTPS = server.useHTTPS
        username = server.username
        password = server.password
        refreshInterval = server.refreshInterval
        clientCertPath = server.clientCertPath ?? ""
        clientCertPassword = server.clientCertPassword ?? ""
        pathMappings = (server.pathMappings ?? []).map(PathMappingDraft.init)
        watchFolderPath = server.watchFolderPath ?? ""
    }

    private var watchFolderTab: some View {
        Form {
            Section {
                TextField(loc("Helyi mappa"), text: $watchFolderPath,
                          prompt: Text(loc("Nincs kiválasztott mappa")))
                    .accessibilityIdentifier("watchFolder.path")
                HStack {
                    Button(loc("Tallózás…"), action: chooseWatchFolder)
                        .accessibilityIdentifier("watchFolder.choose")
                    Button(loc("Eltávolítás")) { watchFolderPath = "" }
                        .disabled(watchFolderPath.isEmpty)
                        .accessibilityIdentifier("watchFolder.clear")
                }
                if !watchFolderIsValid {
                    Text(loc("Adj meg egy / jellel kezdődő helyi útvonalat."))
                        .foregroundStyle(.red)
                } else if watchFolderInUse {
                    Text(loc("Ezt a mappát már egy másik szerver figyeli."))
                        .foregroundStyle(.red)
                }
            } footer: {
                Text(loc("Az app futása közben a mappába kerülő .torrent fájlok automatikusan erre a szerverre kerülnek. A szerver az alapértelmezett letöltési mappáját használja."))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseWatchFolder() {
        let panel = NSOpenPanel()
        panel.title = loc("Figyelt mappa")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if watchFolderPath.hasPrefix("/") { panel.directoryURL = WatchFolders.folderURL(for: watchFolderPath) }
        panel.begin { response in
            if response == .OK, let folder = panel.url {
                watchFolderPath = WatchFolders.folderURL(for: folder.path).path
            }
        }
    }

    private var watchFolderIsValid: Bool { watchFolderPath.isEmpty || watchFolderPath.hasPrefix("/") }

    private var watchFolderInUse: Bool {
        guard watchFolderPath.hasPrefix("/") else { return false }
        let folder = WatchFolders.folderURL(for: watchFolderPath)
        return model.servers.contains {
            guard $0.id != server?.id, let path = $0.watchFolderPath else { return false }
            return WatchFolders.sameFolder(folder, WatchFolders.folderURL(for: path))
        }
    }

    private var mappingsAreValid: Bool {
        (try? PathMapping.validated(pathMappings.filter { !$0.isEmpty }.map(\.mapping))) != nil
    }

    private func save() {
        guard watchFolderIsValid, !watchFolderInUse,
              let mappings = try? PathMapping.validated(pathMappings.filter { !$0.isEmpty }.map(\.mapping)) else { return }
        let config = ServerConfig(
            id: server?.id ?? UUID(),
            name: name,
            host: host,
            port: Int(port) ?? 9091,
            path: path.isEmpty ? "/transmission/rpc" : path,
            useHTTPS: useHTTPS,
            username: username,
            password: password,
            refreshInterval: refreshInterval,
            clientCertPath: clientCertPath.isEmpty ? nil : clientCertPath,
            clientCertPassword: clientCertPassword.isEmpty ? nil : clientCertPassword,
            pathMappings: mappings.isEmpty ? nil : mappings,
            watchFolderPath: watchFolderPath.isEmpty ? nil : WatchFolders.folderURL(for: watchFolderPath).path
        )
        model.addOrUpdate(server: config)
        // Connect to a new server right away.
        if !isEditing {
            model.connect(to: config)
        } else if model.selectedServerID == config.id, model.isConnected {
            model.connect(to: config) // reconnect with the modified settings
        }
        dismiss()
    }
}
