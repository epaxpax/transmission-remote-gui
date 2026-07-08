import Foundation
import Observation

/// Selectable UI language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, hungarian, english
    var id: String { rawValue }

    /// Label shown in the language picker (the system option is intentionally bilingual).
    var title: String {
        switch self {
        case .system: return "Rendszer / System"
        case .hungarian: return "Magyar"
        case .english: return "English"
        }
    }
}

/// Simple, runtime-switchable localization.
///
/// In the source code the **Hungarian** text is the key; in Hungarian mode we return it as-is,
/// in English mode we look it up in the `englishStrings` dictionary (fallback: the key itself).
/// Thanks to `@Observable` + reading `language`, switching languages redraws SwiftUI
/// immediately (no restart needed).
@Observable
final class Localization {
    @MainActor static let shared = Localization()
    private static let key = "appLanguage"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        self.language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The language actually applied: for `.system` it is derived from the system's
    /// preferred language (Hungarian if the system is Hungarian; English otherwise).
    var effective: AppLanguage {
        switch language {
        case .system:
            let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
            return code == "hu" ? .hungarian : .english
        case .hungarian: return .hungarian
        case .english: return .english
        }
    }
}

/// Localized text. `key` is the Hungarian text (which is also the Hungarian value); in English
/// mode it returns the `englishStrings` translation if there is one, otherwise the key itself.
///
/// When called from a body, reading `language` is tracked (@Observable) → re-renders on language change.
@MainActor
func loc(_ key: String) -> String {
    if Localization.shared.effective == .hungarian { return key }
    return englishStrings[key] ?? key
}

/// Hungarian → English translations. Missing keys are shown in Hungarian (grows gradually).
let englishStrings: [String: String] = [
    // General actions / toolbar
    "Hozzáadás": "Add",
    "Indítás": "Start",
    "Leállítás": "Stop",
    "Törlés": "Delete",
    "Frissítés": "Refresh",
    "Szerkesztés": "Edit",
    "Csatlakozás": "Connect",
    "Mégse": "Cancel",
    "Mentés": "Save",
    "Részletek": "Details",
    "Keresés": "Search",
    "Kilépés": "Quit",
    "Nagyítás": "Zoom in",
    "Kicsinyítés": "Zoom out",
    "Eredeti méret": "Actual size",
    // Language / settings
    "Rendszer": "System",
    "Nyelv": "Language",
    "Általános": "General",
    "Szerverek": "Servers",
    "Sebesség": "Speed",
    "Peerek": "Peers",
    "Hálózat": "Network",
    "Sorok": "Queues",
    "Letöltés": "Download",
    "Seedelés": "Seeding",
    // Sidebar filters / state
    "Szűrők": "Filters",
    "Nincs kapcsolat": "Not connected",
    "Csatlakozás…": "Connecting…",
    "Hiba": "Error",
    "Csatlakozva": "Connected",
    "Kiválasztva": "Selected",
    "Dock-ikon megjelenítése": "Show Dock icon",
    "Ablak előtérbe": "Bring window to front",
    // Sidebar filters (TorrentFilter.title keys)
    "Összes": "All",
    "Letöltés alatt": "Downloading",
    "Kész": "Done",
    "Aktív": "Active",
    "Inaktív": "Inactive",
    "Leállítva": "Stopped",
    "Hibás": "Error",
    // Status bar
    "Szabad hely": "Free space",
    "Nincs szerver — ⌘, a beállításokhoz": "No server — ⌘, opens Settings",
    // Toolbar
    "Turtle mód": "Turtle mode",
    "Alternatív sebességkorlát BE — kikapcsolás": "Alternative speed limit ON — turn off",
    "Alternatív sebességkorlát (turtle) bekapcsolása": "Turn on alternative (turtle) speed limit",
    "Részletek panel megjelenítése/elrejtése (⌘I)": "Show/hide the details panel (⌘I)",
    // Torrent list column headers
    "Név": "Name",
    "Állapot": "Status",
    "Méret": "Size",
    "Arány": "Ratio",
    "Hozzáadva": "Added",
    "A szerveren futó Transmission daemon verziója": "Version of the Transmission daemon running on the server",
    // Torrent list empty/error states
    "Válassz szervert a Beállításokban (⌘,)": "Choose a server in Settings (⌘,)",
    "Nincs torrent": "No torrents",
    "Ehhez a szűrőhöz nincs megjeleníthető torrent.": "No torrents match this filter.",
    // Torrent details (General)
    "Letöltve": "Downloaded",
    "Feltöltve": "Uploaded",
    "Letöltési ráta": "Download rate",
    "Feltöltési ráta": "Upload rate",
    "Mappa": "Folder",
    "Megjegyzés": "Comment",
    "Nincs kijelölt torrent": "No torrent selected",
    "Több torrent kijelölve": "Multiple torrents selected",
    // Torrent details tabs + Files
    "Fájlok": "Files",
    "Trackerek": "Trackers",
    "Nincs fájlinformáció": "No file information",
    "Alacsony": "Low",
    "Normál": "Normal",
    "Magas": "High",
    // Peers / Trackers tabs
    "Nincsenek kapcsolódott peerek": "No connected peers",
    "Cím": "Address",
    "Kliens": "Client",
    "Nincs tracker információ": "No tracker information",
    "Seedek": "Seeds",
    "Leecherek": "Leechers",
    // Add torrent dialog
    "Torrent hozzáadása": "Add torrent",
    "Magnet link vagy URL": "Magnet link or URL",
    ".torrent fájl választása": "Choose .torrent file",
    "Leállítva add hozzá": "Add paused",
    // Server edit dialog
    "Szerver szerkesztése": "Edit server",
    "Új szerver": "New server",
    "Hoszt": "Host",
    "RPC útvonal": "RPC path",
    "Felhasználónév (opcionális)": "Username (optional)",
    "Jelszó (opcionális)": "Password (optional)",
    "mp": "s",
    // Delete confirmation + tray
    "Biztosan törlöd a kijelölt torrent(eket)?": "Delete the selected torrent(s)?",
    "Törlés a listából": "Remove from list",
    "Törlés az adatokkal együtt": "Delete along with data",
    "Feltöltés": "Upload",
    // Settings — section titles
    "Sebességlimitek": "Speed limits",
    "Alternatív sebesség (turbó)": "Alternative speed (turbo)",
    "Peer-limitek": "Peer limits",
    "Port": "Port",
    "Protokollok": "Protocols",
    "Titkosítás": "Encryption",
    "Sorkezelés": "Queue management",
    "Blokklista": "Blocklist",
    "Mappák": "Folders",
    "Seedelési limitek": "Seeding limits",
    // Settings — Speed
    "Letöltési limit": "Download limit",
    "Feltöltési limit": "Upload limit",
    "Maximális letöltési sebesség. Kikapcsolva korlátlan.": "Maximum download speed. Unlimited when off.",
    "Maximális feltöltési sebesség. Kikapcsolva korlátlan.": "Maximum upload speed. Unlimited when off.",
    "Turbó mód aktív": "Turbo mode on",
    "A normál limitek helyett az alábbi alternatív sebességek érvényesek.": "The alternative speeds below apply instead of the normal limits.",
    "Alt. letöltés": "Alt. download",
    "Alt. feltöltés": "Alt. upload",
    "Letöltési sebesség turbó módban.": "Download speed in turbo mode.",
    "Feltöltési sebesség turbó módban.": "Upload speed in turbo mode.",
    "Időzített turbó": "Scheduled turbo",
    "A turbó mód automatikus be/kikapcsolása a megadott napszakban.": "Automatically toggles turbo mode during the set time of day.",
    "Kezdés": "Start",
    "Vége": "End",
    "A turbó mód kezdő időpontja (óra:perc).": "Turbo mode start time (hour:minute).",
    "A turbó mód záró időpontja (óra:perc).": "Turbo mode end time (hour:minute).",
    // Settings — Peers
    "Max. peer összesen": "Max peers total",
    "Max. peer torrentenként": "Max peers per torrent",
    "Ennyi kliens (peer) csatlakozhat egyszerre, az összes torrenthez együttvéve.": "This many clients (peers) may connect at once, across all torrents combined.",
    "Egy adott torrenthez ennyi kliens csatlakozhat egyszerre.": "This many clients may connect to a given torrent at once.",
    "Peer port": "Peer port",
    "A bejövő kapcsolatokra figyelt port. Ezt kell átirányítani a routeren.": "The port listened on for incoming connections. Forward this on your router.",
    "Véletlen port induláskor": "Random port on start",
    "A daemon minden indításkor véletlen portot választ (a fenti fix érték helyett).": "The daemon picks a random port on each start (instead of the fixed value above).",
    "Port-továbbítás (UPnP/NAT-PMP)": "Port forwarding (UPnP/NAT-PMP)",
    "A router automatikus portnyitása. Jobb elérhetőség, ha a router támogatja.": "Automatic port opening on the router. Better reachability if the router supports it.",
    "PEX (Peer Exchange)": "PEX (Peer Exchange)",
    "Peerek cseréje a már kapcsolódó kliensekkel. Több elérhető peer.": "Exchange peers with already-connected clients. More available peers.",
    "DHT": "DHT",
    "Elosztott hash-tábla: peerek keresése tracker nélkül is.": "Distributed hash table: find peers even without a tracker.",
    "LPD (helyi felfedezés)": "LPD (Local Peer Discovery)",
    "Peerek keresése a helyi hálózaton (LAN).": "Discover peers on the local network (LAN).",
    "µTP": "µTP",
    "Micro Transport Protocol: forgalomszabályozás, hogy ne fojtsa meg a többi kapcsolatot.": "Micro Transport Protocol: traffic shaping so it does not choke other connections.",
    "Peer-titkosítás": "Peer encryption",
    "Kötelező: csak titkosított kapcsolat. Előnyben részesített: ha lehet, titkosít. Megengedő: elfogad titkosítatlant is.": "Required: encrypted only. Preferred: encrypt if possible. Tolerated: accepts unencrypted too.",
    "Jelenleg használatban": "Currently in use",
    "Aktív letöltések száma": "Active downloads",
    "Aktív seedelések száma": "Active seeds",
    "Az összes torrenten most csatlakozó kliensek száma a globális limithez képest.": "Number of clients currently connected across all torrents, relative to the global limit.",
    // Settings — Queues
    "Egyszerre letöltők korlátozása": "Limit active downloads",
    "Ha be van kapcsolva, egyszerre csak ennyi torrent tölt aktívan, a többi sorban vár.": "When on, only this many torrents download actively; the rest wait in the queue.",
    "A letöltési sorban egyszerre aktív torrentek maximuma.": "Maximum torrents active in the download queue at once.",
    "Egyszerre seedelők korlátozása": "Limit active seeds",
    "Ha be van kapcsolva, egyszerre csak ennyi torrent seedel aktívan.": "When on, only this many torrents seed actively.",
    "A seed sorban egyszerre aktív torrentek maximuma.": "Maximum torrents active in the seed queue at once.",
    "Elakadtnak jelölés": "Mark as stalled",
    "Ha egy torrent a megadott ideig nem forgalmaz, elakadtként kezeli (kikerül az aktív sorból).": "If a torrent has no traffic for the given time, it is treated as stalled (removed from the active queue).",
    "Elakadtság ideje": "Stall time",
    "Ennyi perc forgalommentesség után számít elakadtnak.": "Counts as stalled after this many minutes without traffic.",
    // Settings — Download
    "Letöltési mappa": "Download folder",
    "A daemon ide menti a kész (és folyamatban lévő) letöltéseket. A daemon gépén értendő útvonal.": "The daemon saves finished (and in-progress) downloads here. Path on the daemon's machine.",
    "Befejezetlenek külön mappában": "Incomplete files in a separate folder",
    "A folyamatban lévő letöltések egy külön ideiglenes mappába kerülnek, majd készen átmozgatja.": "In-progress downloads go to a separate temporary folder, then move over when finished.",
    "Befejezetlenek mappája": "Incomplete folder",
    "A folyamatban lévő letöltések ideiglenes helye.": "Temporary location for in-progress downloads.",
    "Befejezetlen fájlok „.part” végződése": "\".part\" suffix for incomplete files",
    "A még nem kész fájlok neve .part kiterjesztést kap, amíg le nem töltődnek.": "Not-yet-finished files get a .part extension until they download.",
    "Azonnali indítás hozzáadáskor": "Start immediately when added",
    "A hozzáadott torrentek rögtön elindulnak (nem szüneteltetve kerülnek be).": "Added torrents start right away (they are not added paused).",
    // Settings — Seeding
    "Seedelés arány-limitig": "Seed to ratio limit",
    "A torrentek automatikus leállítása, ha elérik a megadott feltöltés/letöltés arányt.": "Automatically stops torrents when they reach the given upload/download ratio.",
    "Cél feltöltési arány (pl. 2,0 = kétszer annyit tölt fel, mint le).": "Target upload ratio (e.g. 2.0 = uploads twice as much as downloaded).",
    "Leállítás tétlenség után": "Stop after idle",
    "A seedelés automatikus leállítása, ha a megadott ideig nincs aktivitás.": "Automatically stops seeding if there is no activity for the given time.",
    "Tétlenségi idő": "Idle time",
    "Ennyi perc aktivitásmentesség után leáll a seedelés.": "Seeding stops after this many minutes of inactivity.",
    // Settings — Blocklist
    "Blokklista aktív": "Blocklist enabled",
    "Ismert rosszindulatú/nem kívánt IP-tartományok tiltása.": "Block known malicious/unwanted IP ranges.",
    "Blokklista URL": "Blocklist URL",
    "A letöltendő blokklista címe.": "URL of the blocklist to download.",
    // ServersTab additions
    "Nincs szerver": "No server",
    "Adj hozzá egy Transmission szervert a + gombbal.": "Add a Transmission server with the + button.",
    "Szerver hozzáadása": "Add server",
    "Kijelölt szerver törlése": "Delete selected server",
    // Toolbar — more actions
    "Egyéb műveletek": "More actions",
    "Ellenőrzés (verify)": "Verify",
    "Újrabejelentés a trackernek": "Reannounce to tracker",
    "Streaming (sorrendi) letöltés be": "Enable streaming (sequential)",
    "Streaming letöltés ki": "Disable streaming",
    "Sorrendi letöltéshez Transmission 4.1+ szükséges": "Sequential download requires Transmission 4.1+",
    // Ütemező — napok
    "Napok": "Days",
    "Mely napokon lépjen életbe az időzített turbó.": "Which days the scheduled turbo applies on.",
    // Statisztika panel
    "Statisztika": "Statistics",
    "Összes letöltve": "Total downloaded",
    "Összes feltöltve": "Total uploaded",
    "Aktív torrentek": "Active torrents",
    // Settings — missing section/row titles + Picker
    "Alternatív („turbó”) sebesség": "Alternative (\"turbo\") speed",
    "Kliens-limitek": "Client limits",
    "Peer-felfedezés": "Peer discovery",
    "Letöltési sor": "Download queue",
    "Seed sor": "Seed queue",
    "Elakadt torrentek": "Stalled torrents",
    "Új torrentek": "New torrents",
    "Arány-limit": "Ratio limit",
    "Tétlen seedelés": "Idle seeding",
    "Inaktivitás": "Inactivity",
    "szabály betöltve": "rules loaded",
    "Elérted a globális peer-limitet — ha több kapcsolat kellene, emeld meg lentebb.": "You've reached the global peer limit — raise it below if you need more connections.",
    // Peer encryption Picker (Encryption.title)
    "Kötelező": "Required",
    "Előnyben részesített": "Preferred",
    "Megengedő": "Tolerated",
]

/// Torrent status translations — SEPARATE from the main dictionary, because the Hungarian
/// key for "download" is "Downloading" here, while as a Settings tab name it is "Download"
/// (it would be a key collision in a single dictionary).
private let statusEnglish: [String: String] = [
    "Leállítva": "Stopped",
    "Ellenőrzésre vár": "Queued to verify",
    "Letöltésre vár": "Queued to download",
    "Letöltés": "Downloading",
    "Seedelésre vár": "Queued to seed",
    "Seedelés": "Seeding",
]

/// Translates the Hungarian output of `Torrent.statusText` to the current language.
@MainActor
func locStatus(_ hungarian: String) -> String {
    if Localization.shared.effective == .hungarian { return hungarian }
    // For a "Verifying 45%"-style status: translate the prefix, keep the percentage.
    let verifyPrefix = "Ellenőrzés "
    if hungarian.hasPrefix(verifyPrefix) {
        return "Verifying " + hungarian.dropFirst(verifyPrefix.count)
    }
    return statusEnglish[hungarian] ?? hungarian
}

