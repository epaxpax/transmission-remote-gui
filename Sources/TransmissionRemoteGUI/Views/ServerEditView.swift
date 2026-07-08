import SwiftUI
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

    private var isEditing: Bool { server != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? loc("Szerver szerkesztése") : loc("Új szerver"))
                .font(.title2.bold())
                .padding(.bottom, 12)

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
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(loc("Mégse")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? loc("Mentés") : loc("Hozzáadás")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || host.isEmpty)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 460, height: 460)
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
    }

    private func save() {
        let config = ServerConfig(
            id: server?.id ?? UUID(),
            name: name,
            host: host,
            port: Int(port) ?? 9091,
            path: path.isEmpty ? "/transmission/rpc" : path,
            useHTTPS: useHTTPS,
            username: username,
            password: password,
            refreshInterval: refreshInterval
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
