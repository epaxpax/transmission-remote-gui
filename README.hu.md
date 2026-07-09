# Transmission Remote GUI

Natív **SwiftUI macOS** távoli vezérlő ("remote GUI") a [Transmission](https://transmissionbt.com/)
BitTorrent-daemonhoz, az RPC protokollon keresztül. A klasszikus
[transgui](https://github.com/transmission-remote-gui/transgui) (Lazarus/Free Pascal) modern,
tiszta lapról írt macOS-újragondolása.

> **Clean-room reimplementáció:** csak a funkciókat veszi alapul, más projekt kódját nem.
> A teljes forrás önállóan, Swiftben íródott.

*English description: [README.md](README.md)*

## Funkciók

- Torrent-lista oszlopokkal (név, állapot, haladás, méret, ↓/↑ ráta, ETA, arány, peerek), gyors natív rendezéssel
- Sidebar szűrők + darabszámok (Összes / Letöltés alatt / Kész / Aktív / Inaktív / Leállítva / Hibás), plusz **címke (kategória) szűrők**
- Keresés a listában
- Torrent hozzáadása **magnet linkből / URL-ből**, **`.torrent` fájlból**, valamint **drag & drop**pal az ablakra
- Indítás / leállítás / törlés (opcionálisan az adatokkal együtt), **ellenőrzés (verify)** és **újrabejelentés (reannounce)**
- **Részletek panel** (⌘I) tabokkal: **Általános / Fájlok / Peerek / Trackerek**; fájlonkénti szelekció és prioritás; **torrentenkénti sebességkorlát**; **címkék/kategóriák** szerkesztése
- **RSS auto-letöltő** — figyelt feed-ek + cím-szűrő szabályok (tartalmazás vagy `/regex/`) → automatikus torrent-hozzáadás, duplikátum-szűréssel
- **mTLS kliens-tanúsítvány** hitelesítés (opcionális `.p12` szerverenként) olyan reverse proxyhoz, ami megköveteli
- **Sebesség-grafikon** — élő mini-chart a sidebarban, részletes **Statisztika panel**, és Stats-szerű **menüsor-popover**
- **Sorrendi („streaming") letöltés** (Transmission 4.1+) — a darabok sorrendben töltődnek, így a média nézhető letöltés közben; hivatalos GUI/Web UI még nem tudja
- **Több szerver**, kezelés a Beállításokban; a jelszó a **Keychain**ben; **induláskori auto-connect** a legutóbbi szerverhez
- Teljes **session-beállítások** (sebesség, peerek, hálózat, sorok, letöltés, seedelés) — azonnali `session-set` írással
- **Turtle mód** egy kattintással, plusz **sávszélesség-ütemező** (turbó automatikus be/ki napszak és hét napja szerint)
- **Értesítés** a torrent letöltésének befejeződésekor
- **Menüsor (tray) ikon** le/fel sebességgel és élő grafikonnal; a **Dock-ikon elrejthető** (csak a menüsorban él)
- UI-nagyítás (⌘+ / ⌘− / ⌘0), automatikus, állítható időközű frissítés
- **Kétnyelvű felület**: angol és magyar, futásidőben váltható (Beállítások → Általános)

## Felépítés

| Réteg | Tartalom |
|-------|----------|
| `TransmissionKit` | UI-független mag: `RPCClient` (409 handshake, basic auth), Codable modellek, tipizált RPC-wrapperek, formázók. Tesztelhető daemon nélkül. |
| `TransmissionRemoteGUI` | SwiftUI app: `AppModel` (`@Observable`), `NavigationSplitView` + inspector, tray, beállítások. |
| `KitTests` | Önálló teszt-futtató (a CLT toolchainben nincs XCTest). |

A kliens a **klasszikus** Transmission RPC protokollra céloz
(`{"method":"torrent-get","arguments":{…},"tag":N}`, camelCase mezők), amelyet a Transmission
3.x és 4.0.x használ (a 4.1+ daemonok visszafelé kompatibilisen szintén).

## Követelmények

- macOS 14+
- Swift 6 toolchain (teljes Xcode **nem** szükséges, a Command Line Tools elég)

## Build / futtatás / teszt

```sh
swift build                            # fordítás
swift run TransmissionRemoteGUI        # app indítása (fejlesztéshez)
swift run KitTests                     # egységtesztek (RPC envelope, 409 handshake, modell-dekódolás, URL-normalizálás)
```

### Telepíthető `.app` bundle

Teljes Xcode nélkül is előállítható egy dupla-kattintható alkalmazás:

```sh
./Scripts/build-app.sh          # → "dist/Transmission Remote GUI.app" (release build, ikon, ad-hoc aláírás)
./Scripts/build-app.sh --dmg    # + hordozható .dmg
```

Ezután húzd a **Transmission Remote GUI.app**-ot az `/Applications` mappába. Az ad-hoc aláírás miatt
a bundle a saját gépeden fut; más gépre való terjesztéshez Apple Developer ID + notarizáció kell.

### Homebrew

```sh
brew install --cask epaxpax/tap/transmission-remote-gui-macos
```

Az `/Applications`-be telepít. Ad-hoc aláírt (nem notarizált) — a cask leveszi a letöltési
karantént, így Gatekeeper-figyelmeztetés nélkül indul. A `-macos` utótag elkerüli a névütközést
a Homebrew core (elavult) `transmission-remote-gui` cask-jával.

### Tesztelés valódi daemonnal

```sh
brew install transmission-cli
transmission-daemon --foreground --port 9091
# majd az appban: Beállítások (⌘,) → Szerverek → +  →  127.0.0.1 : 9091
```

## Későbbi lehetőségek

- Letöltési sor (queue) mozgatás
- Torrent áthelyezése (set-location), tracker hozzáadás/törlés, átnevezés
- Watch-folder
- Jobbklikk (context) menü, oszlop-testreszabás
- JSON-RPC 2.0 (Transmission 4.1+) támogatás

## Licenc

[MIT](LICENSE) © 2026 Viktor Falcsik
