import SwiftUI
import TransmissionKit

/// The daemon's global settings (`session-get` / `session-set`), in a tabbed layout.
/// Every control applies the change on the server immediately (`updateSession`), then
/// reloads the fresh state — so external changes are visible right away too.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            // General (language) — always available.
            GeneralSettingsTab().tabItem { Label(loc("Általános"), systemImage: "gearshape") }

            // Server management — available without a connection (connecting starts here).
            ServersSettingsTab().tabItem { Label(loc("Szerverek"), systemImage: "server.rack") }

            // The daemon's global settings — only with a live connection.
            if model.sessionInfo != nil {
                SpeedSettingsTab().tabItem { Label(loc("Sebesség"), systemImage: "speedometer") }
                PeerSettingsTab().tabItem { Label(loc("Peerek"), systemImage: "person.2") }
                NetworkSettingsTab().tabItem { Label(loc("Hálózat"), systemImage: "network") }
                QueueSettingsTab().tabItem { Label(loc("Sorok"), systemImage: "list.number") }
                DownloadSettingsTab().tabItem { Label(loc("Letöltés"), systemImage: "arrow.down.circle") }
                SeedingSettingsTab().tabItem { Label(loc("Seedelés"), systemImage: "arrow.up.circle") }
            }
        }
    }
}

// MARK: - General (language)

/// Language picker (System / Hungarian / English) — switches immediately.
private struct GeneralSettingsTab: View {
    @Bindable private var l10n = Localization.shared

    var body: some View {
        Form {
            Picker(loc("Nyelv"), selection: $l10n.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.title).tag(lang)
                }
            }
            .pickerStyle(.inline)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Servers

/// Server list + management (add/edit/delete/connect). Moved here from the sidebar
/// to keep the main window clean; for the launch-time auto-connect see
/// `AppModel.autoConnectIfNeeded()`.
private struct ServersSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var selection: ServerConfig.ID?
    @State private var sheet: ServerSheet?

    /// Target of the server-edit sheet — for `.sheet(item:)` (robust against state timing,
    /// unlike the `.sheet(isPresented:)` + separate state combination).
    private enum ServerSheet: Identifiable {
        case add
        case edit(ServerConfig)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let s): return s.id.uuidString
            }
        }
        var server: ServerConfig? {
            if case .edit(let s) = self { return s }
            return nil
        }
    }

    private var selectedServer: ServerConfig? {
        guard let selection else { return nil }
        return model.servers.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.servers.isEmpty {
                ContentUnavailableView(
                    loc("Nincs szerver"),
                    systemImage: "server.rack",
                    description: Text(loc("Adj hozzá egy Transmission szervert a + gombbal."))
                )
            } else {
                // Custom selection (not List(selection:), which is unreliable here on macOS):
                // single click on a row → select, double click → connect.
                List {
                    ForEach(model.servers) { server in
                        row(server)
                            .listRowBackground(selection == server.id ? Color.accentColor.opacity(0.18) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.connect(to: server) }
                            .onTapGesture { selection = server.id }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                Button { sheet = .add } label: { Image(systemName: "plus") }
                    .help(loc("Szerver hozzáadása"))

                Button {
                    if let s = selectedServer { model.deleteServer(s); selection = nil }
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .help(loc("Kijelölt szerver törlése"))

                Spacer()

                Button(loc("Szerkesztés")) {
                    if let s = selectedServer { sheet = .edit(s) }
                }
                .disabled(selection == nil)

                Button(loc("Csatlakozás")) {
                    if let s = selectedServer { model.connect(to: s) }
                }
                .disabled(selection == nil)
            }
            .padding(8)
        }
        .sheet(item: $sheet) { target in
            ServerEditView(server: target.server).environment(model)
        }
    }

    @ViewBuilder
    private func row(_ server: ServerConfig) -> some View {
        let isCurrent = model.selectedServerID == server.id
        HStack(spacing: 10) {
            Image(systemName: isCurrent && model.isConnected ? "network" : "network.slash")
                .foregroundStyle(isCurrent && model.isConnected ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(server.name)
                Text("\(server.host):\(server.port)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Text(model.isConnected ? loc("Csatlakozva") : loc("Kiválasztva"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared elements

/// A single settings row: title + control on the right, with an explanatory description below.
private struct SettingRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(loc(title))
                Spacer(minLength: 12)
                control()
            }
            Text(loc(description))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

/// Produces Bindings between `SessionInfo` (get) and `SessionSetArgs` (set).
/// The setter optimistically updates the local state right away (`model.editSession`), then
/// sends it to the server in the background — so controls react to the click instantly.
@MainActor
private struct SessionBinder {
    let model: AppModel

    func bool(_ path: WritableKeyPath<SessionInfo, Bool?>, default def: Bool = false,
              apply: @escaping (inout SessionSetArgs, Bool) -> Void) -> Binding<Bool> {
        Binding(
            get: { model.sessionInfo?[keyPath: path] ?? def },
            set: { v in model.editSession(path, to: v) { apply(&$0, v) } }
        )
    }

    func int(_ path: WritableKeyPath<SessionInfo, Int?>, default def: Int = 0,
             apply: @escaping (inout SessionSetArgs, Int) -> Void) -> Binding<Int> {
        Binding(
            get: { model.sessionInfo?[keyPath: path] ?? def },
            set: { v in model.editSession(path, to: v) { apply(&$0, v) } }
        )
    }

    func double(_ path: WritableKeyPath<SessionInfo, Double?>, default def: Double = 0,
                apply: @escaping (inout SessionSetArgs, Double) -> Void) -> Binding<Double> {
        Binding(
            get: { model.sessionInfo?[keyPath: path] ?? def },
            set: { v in model.editSession(path, to: v) { apply(&$0, v) } }
        )
    }

    func string(_ path: WritableKeyPath<SessionInfo, String?>, default def: String = "",
                apply: @escaping (inout SessionSetArgs, String) -> Void) -> Binding<String> {
        Binding(
            get: { model.sessionInfo?[keyPath: path] ?? def },
            set: { v in model.editSession(path, to: v) { apply(&$0, v) } }
        )
    }
}

@MainActor
private func formStyled<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    Form { content() }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// MARK: - Tabs

private struct SpeedSettingsTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let b = SessionBinder(model: model)
        return formStyled {
            Section(loc("Sebességlimitek")) {
                SettingRow(title: "Letöltési limit", description: "Maximális letöltési sebesség. Kikapcsolva korlátlan.") {
                    HStack {
                        TextField("", value: b.int(\.speedLimitDown) { $0.speedLimitDown = $1 }, format: .number)
                            .frame(width: 70).multilineTextAlignment(.trailing).labelsHidden()
                            .disabled(!(model.sessionInfo?.speedLimitDownEnabled ?? false))
                        Text("kB/s").foregroundStyle(.secondary)
                        Toggle("", isOn: b.bool(\.speedLimitDownEnabled) { $0.speedLimitDownEnabled = $1 }).labelsHidden()
                    }
                }
                SettingRow(title: "Feltöltési limit", description: "Maximális feltöltési sebesség. Kikapcsolva korlátlan.") {
                    HStack {
                        TextField("", value: b.int(\.speedLimitUp) { $0.speedLimitUp = $1 }, format: .number)
                            .frame(width: 70).multilineTextAlignment(.trailing).labelsHidden()
                            .disabled(!(model.sessionInfo?.speedLimitUpEnabled ?? false))
                        Text("kB/s").foregroundStyle(.secondary)
                        Toggle("", isOn: b.bool(\.speedLimitUpEnabled) { $0.speedLimitUpEnabled = $1 }).labelsHidden()
                    }
                }
            }

            Section(loc("Alternatív („turbó”) sebesség")) {
                SettingRow(title: "Turbó mód aktív", description: "A normál limitek helyett az alábbi alternatív sebességek érvényesek.") {
                    Toggle("", isOn: b.bool(\.altSpeedEnabled) { $0.altSpeedEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "Alt. letöltés", description: "Letöltési sebesség turbó módban.") {
                    HStack {
                        TextField("", value: b.int(\.altSpeedDown) { $0.altSpeedDown = $1 }, format: .number)
                            .frame(width: 70).multilineTextAlignment(.trailing).labelsHidden()
                        Text("kB/s").foregroundStyle(.secondary)
                    }
                }
                SettingRow(title: "Alt. feltöltés", description: "Feltöltési sebesség turbó módban.") {
                    HStack {
                        TextField("", value: b.int(\.altSpeedUp) { $0.altSpeedUp = $1 }, format: .number)
                            .frame(width: 70).multilineTextAlignment(.trailing).labelsHidden()
                        Text("kB/s").foregroundStyle(.secondary)
                    }
                }
                SettingRow(title: "Időzített turbó", description: "A turbó mód automatikus be/kikapcsolása a megadott napszakban.") {
                    Toggle("", isOn: b.bool(\.altSpeedTimeEnabled) { $0.altSpeedTimeEnabled = $1 }).labelsHidden()
                }
                if model.sessionInfo?.altSpeedTimeEnabled ?? false {
                    SettingRow(title: "Kezdés", description: "A turbó mód kezdő időpontja (óra:perc).") {
                        TimeField(minutes: b.int(\.altSpeedTimeBegin) { $0.altSpeedTimeBegin = $1 })
                    }
                    SettingRow(title: "Vége", description: "A turbó mód záró időpontja (óra:perc).") {
                        TimeField(minutes: b.int(\.altSpeedTimeEnd) { $0.altSpeedTimeEnd = $1 })
                    }
                }
            }
        }
    }
}

private struct PeerSettingsTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let b = SessionBinder(model: model)
        return formStyled {
            Section(loc("Kliens-limitek")) {
                PeerUsageRow(used: model.totalConnectedPeers, limit: model.sessionInfo?.peerLimitGlobal ?? 0)
                SettingRow(title: "Max. peer összesen", description: "Ennyi kliens (peer) csatlakozhat egyszerre, az összes torrenthez együttvéve.") {
                    Stepper(value: b.int(\.peerLimitGlobal, default: 200) { $0.peerLimitGlobal = $1 }, in: 1...9999, step: 10) {
                        Text("\(model.sessionInfo?.peerLimitGlobal ?? 0)").monospacedDigit().frame(minWidth: 44, alignment: .trailing)
                    }
                }
                SettingRow(title: "Max. peer torrentenként", description: "Egy adott torrenthez ennyi kliens csatlakozhat egyszerre.") {
                    Stepper(value: b.int(\.peerLimitPerTorrent, default: 50) { $0.peerLimitPerTorrent = $1 }, in: 1...9999, step: 5) {
                        Text("\(model.sessionInfo?.peerLimitPerTorrent ?? 0)").monospacedDigit().frame(minWidth: 44, alignment: .trailing)
                    }
                }
            }

            Section(loc("Port")) {
                SettingRow(title: "Peer port", description: "A bejövő kapcsolatokra figyelt port. Ezt kell átirányítani a routeren.") {
                    TextField("", value: b.int(\.peerPort, default: 51413) { $0.peerPort = $1 }, format: .number)
                        .frame(width: 80).multilineTextAlignment(.trailing).labelsHidden()
                        .disabled(model.sessionInfo?.peerPortRandomOnStart ?? false)
                }
                SettingRow(title: "Véletlen port induláskor", description: "A daemon minden indításkor véletlen portot választ (a fenti fix érték helyett).") {
                    Toggle("", isOn: b.bool(\.peerPortRandomOnStart) { $0.peerPortRandomOnStart = $1 }).labelsHidden()
                }
                SettingRow(title: "Port-továbbítás (UPnP/NAT-PMP)", description: "A router automatikus portnyitása. Jobb elérhetőség, ha a router támogatja.") {
                    Toggle("", isOn: b.bool(\.portForwardingEnabled) { $0.portForwardingEnabled = $1 }).labelsHidden()
                }
            }

            Section(loc("Titkosítás")) {
                SettingRow(title: "Peer-titkosítás", description: "Kötelező: csak titkosított kapcsolat. Előnyben részesített: ha lehet, titkosít. Megengedő: elfogad titkosítatlant is.") {
                    Picker("", selection: Binding(
                        get: { model.sessionInfo?.encryptionValue ?? .preferred },
                        set: { v in model.editSession(\.encryption, to: v.rawValue) { $0.encryption = v.rawValue } }
                    )) {
                        ForEach(Encryption.allCases, id: \.self) { Text(loc($0.title)).tag($0) }
                    }
                    .labelsHidden().frame(width: 180)
                }
            }
        }
    }
}

private struct NetworkSettingsTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let b = SessionBinder(model: model)
        return formStyled {
            Section(loc("Peer-felfedezés")) {
                SettingRow(title: "PEX (Peer Exchange)", description: "Peerek cseréje a már kapcsolódó kliensekkel. Több elérhető peer.") {
                    Toggle("", isOn: b.bool(\.pexEnabled) { $0.pexEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "DHT", description: "Elosztott hash-tábla: peerek keresése tracker nélkül is.") {
                    Toggle("", isOn: b.bool(\.dhtEnabled) { $0.dhtEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "LPD (helyi felfedezés)", description: "Peerek keresése a helyi hálózaton (LAN).") {
                    Toggle("", isOn: b.bool(\.lpdEnabled) { $0.lpdEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "µTP", description: "Micro Transport Protocol: forgalomszabályozás, hogy ne fojtsa meg a többi kapcsolatot.") {
                    Toggle("", isOn: b.bool(\.utpEnabled) { $0.utpEnabled = $1 }).labelsHidden()
                }
            }

            Section {
                SettingRow(title: "Blokklista aktív", description: "Ismert rosszindulatú/nem kívánt IP-tartományok tiltása.") {
                    Toggle("", isOn: b.bool(\.blocklistEnabled) { $0.blocklistEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "Blokklista URL", description: "A letöltendő blokklista címe.") {
                    TextField("", text: b.string(\.blocklistUrl) { $0.blocklistUrl = $1 })
                        .frame(width: 200).labelsHidden()
                        .disabled(!(model.sessionInfo?.blocklistEnabled ?? false))
                }
            } header: {
                Text(loc("Blokklista"))
            } footer: {
                if let size = model.sessionInfo?.blocklistSize, size > 0 {
                    Text("\(size) " + loc("szabály betöltve")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct QueueSettingsTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let b = SessionBinder(model: model)
        return formStyled {
            Section(loc("Letöltési sor")) {
                SettingRow(title: "Egyszerre letöltők korlátozása", description: "Ha be van kapcsolva, egyszerre csak ennyi torrent tölt aktívan, a többi sorban vár.") {
                    Toggle("", isOn: b.bool(\.downloadQueueEnabled) { $0.downloadQueueEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "Aktív letöltések száma", description: "A letöltési sorban egyszerre aktív torrentek maximuma.") {
                    Stepper(value: b.int(\.downloadQueueSize, default: 5) { $0.downloadQueueSize = $1 }, in: 1...100) {
                        Text("\(model.sessionInfo?.downloadQueueSize ?? 0)").monospacedDigit().frame(minWidth: 32, alignment: .trailing)
                    }
                    .disabled(!(model.sessionInfo?.downloadQueueEnabled ?? false))
                }
            }

            Section(loc("Seed sor")) {
                SettingRow(title: "Egyszerre seedelők korlátozása", description: "Ha be van kapcsolva, egyszerre csak ennyi torrent seedel aktívan.") {
                    Toggle("", isOn: b.bool(\.seedQueueEnabled) { $0.seedQueueEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "Aktív seedelések száma", description: "A seed sorban egyszerre aktív torrentek maximuma.") {
                    Stepper(value: b.int(\.seedQueueSize, default: 5) { $0.seedQueueSize = $1 }, in: 1...100) {
                        Text("\(model.sessionInfo?.seedQueueSize ?? 0)").monospacedDigit().frame(minWidth: 32, alignment: .trailing)
                    }
                    .disabled(!(model.sessionInfo?.seedQueueEnabled ?? false))
                }
            }

            Section(loc("Elakadt torrentek")) {
                SettingRow(title: "Elakadtnak jelölés", description: "Ha egy torrent a megadott ideig nem forgalmaz, elakadtként kezeli (kikerül az aktív sorból).") {
                    Toggle("", isOn: b.bool(\.queueStalledEnabled) { $0.queueStalledEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "Inaktivitás", description: "Ennyi perc forgalommentesség után számít elakadtnak.") {
                    Stepper(value: b.int(\.queueStalledMinutes, default: 30) { $0.queueStalledMinutes = $1 }, in: 1...1440, step: 5) {
                        Text("\(model.sessionInfo?.queueStalledMinutes ?? 0) perc").monospacedDigit().frame(minWidth: 60, alignment: .trailing)
                    }
                    .disabled(!(model.sessionInfo?.queueStalledEnabled ?? false))
                }
            }
        }
    }
}

private struct DownloadSettingsTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let b = SessionBinder(model: model)
        return formStyled {
            Section(loc("Mappák")) {
                SettingRow(title: "Letöltési mappa", description: "A daemon ide menti a kész (és folyamatban lévő) letöltéseket. A daemon gépén értendő útvonal.") {
                    TextField("", text: b.string(\.downloadDir) { $0.downloadDir = $1 })
                        .frame(width: 240).labelsHidden()
                }
                SettingRow(title: "Befejezetlenek külön mappában", description: "A folyamatban lévő letöltések egy külön ideiglenes mappába kerülnek, majd készen átmozgatja.") {
                    Toggle("", isOn: b.bool(\.incompleteDirEnabled) { $0.incompleteDirEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "Befejezetlenek mappája", description: "A folyamatban lévő letöltések ideiglenes helye.") {
                    TextField("", text: b.string(\.incompleteDir) { $0.incompleteDir = $1 })
                        .frame(width: 240).labelsHidden()
                        .disabled(!(model.sessionInfo?.incompleteDirEnabled ?? false))
                }
            }

            Section(loc("Új torrentek")) {
                SettingRow(title: "Azonnali indítás hozzáadáskor", description: "A hozzáadott torrentek rögtön elindulnak (nem szüneteltetve kerülnek be).") {
                    Toggle("", isOn: b.bool(\.startAddedTorrents) { $0.startAddedTorrents = $1 }).labelsHidden()
                }
                SettingRow(title: "Befejezetlen fájlok „.part” végződése", description: "A még nem kész fájlok neve .part kiterjesztést kap, amíg le nem töltődnek.") {
                    Toggle("", isOn: b.bool(\.renamePartialFiles) { $0.renamePartialFiles = $1 }).labelsHidden()
                }
            }
        }
    }
}

private struct SeedingSettingsTab: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let b = SessionBinder(model: model)
        return formStyled {
            Section(loc("Arány-limit")) {
                SettingRow(title: "Seedelés arány-limitig", description: "A torrentek automatikus leállítása, ha elérik a megadott feltöltés/letöltés arányt.") {
                    Toggle("", isOn: b.bool(\.seedRatioLimited) { $0.seedRatioLimited = $1 }).labelsHidden()
                }
                SettingRow(title: "Arány", description: "Cél feltöltési arány (pl. 2,0 = kétszer annyit tölt fel, mint le).") {
                    TextField("", value: b.double(\.seedRatioLimit, default: 2) { $0.seedRatioLimit = $1 }, format: .number)
                        .frame(width: 70).multilineTextAlignment(.trailing).labelsHidden()
                        .disabled(!(model.sessionInfo?.seedRatioLimited ?? false))
                }
            }

            Section(loc("Tétlen seedelés")) {
                SettingRow(title: "Leállítás tétlenség után", description: "A seedelés automatikus leállítása, ha a megadott ideig nincs aktivitás.") {
                    Toggle("", isOn: b.bool(\.idleSeedingLimitEnabled) { $0.idleSeedingLimitEnabled = $1 }).labelsHidden()
                }
                SettingRow(title: "Tétlenségi idő", description: "Ennyi perc aktivitásmentesség után leáll a seedelés.") {
                    Stepper(value: b.int(\.idleSeedingLimit, default: 30) { $0.idleSeedingLimit = $1 }, in: 1...1440, step: 5) {
                        Text("\(model.sessionInfo?.idleSeedingLimit ?? 0) perc").monospacedDigit().frame(minWidth: 60, alignment: .trailing)
                    }
                    .disabled(!(model.sessionInfo?.idleSeedingLimitEnabled ?? false))
                }
            }
        }
    }
}

// MARK: - Peer usage indicator

/// Live indicator: how many clients are connected now relative to the global limit. The bar's
/// color goes green → orange → red as it approaches the limit; warns when full.
private struct PeerUsageRow: View {
    let used: Int
    let limit: Int

    private var fraction: Double { limit > 0 ? min(1, Double(used) / Double(limit)) : 0 }
    private var color: Color {
        switch fraction {
        case 0.9...: return .red
        case 0.7...: return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(loc("Jelenleg használatban"))
                Spacer()
                Text("\(used) / \(limit)").monospacedDigit().foregroundStyle(color).bold()
            }
            ProgressView(value: fraction).tint(color)
            if limit > 0, used >= limit {
                Label(loc("Elérted a globális peer-limitet — ha több kapcsolat kellene, emeld meg lentebb."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(loc("Az összes torrenten most csatlakozó kliensek száma a globális limithez képest."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Time (minutes since midnight) editor

/// Hour:minute editor for Transmission's "minutes since midnight" style fields.
private struct TimeField: View {
    @Binding var minutes: Int

    var body: some View {
        DatePicker("", selection: Binding(
            get: {
                let comps = DateComponents(hour: minutes / 60, minute: minutes % 60)
                return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 0)
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .datePickerStyle(.stepperField)
    }
}
