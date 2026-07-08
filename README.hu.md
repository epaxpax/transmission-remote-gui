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
- Sidebar szűrők + darabszámok: Összes / Letöltés alatt / Kész / Aktív / Inaktív / Leállítva / Hibás
- Keresés a listában
- Torrent hozzáadása **magnet linkből / URL-ből**, **`.torrent` fájlból**, valamint **drag & drop**pal az ablakra
- Indítás / leállítás / törlés (opcionálisan az adatokkal együtt)
- **Részletek panel** (⌘I-vel kapcsolható inspector) tabokkal: **Általános / Fájlok / Peerek / Trackerek**
  - Fájlonkénti letöltés-szelekció (wanted) és prioritás
- **Több szerver**, kezelés a Beállításokban; a jelszó a **Keychain**ben; **induláskori auto-connect** a legutóbbi szerverhez
- Teljes **session-beállítások** (sebesség, peerek, hálózat, sorok, letöltés, seedelés) — azonnali `session-set` írással
- **Turtle mód** (alternatív sebességkorlát) egy kattintással a toolbarból
- **Értesítés** a torrent letöltésének befejeződésekor
- **Menüsor (tray) ikon** le/fel sebességgel; a **Dock-ikon elrejthető** (csak a menüsorban él)
- UI-nagyítás (⌘+ / ⌘− / ⌘0), automatikus, állítható időközű frissítés

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
brew install epaxpax/tap/transmission-remote-gui    # forrásból buildel és telepít
```

*(A tap a nyilvános repo közzététele után lesz elérhető — lásd `Formula/transmission-remote-gui.rb`.)*

### Tesztelés valódi daemonnal

```sh
brew install transmission-cli
transmission-daemon --foreground --port 9091
# majd az appban: Beállítások (⌘,) → Szerverek → +  →  127.0.0.1 : 9091
```

## Későbbi lehetőségek

- Per-torrent sebességkorlát, letöltési sor (queue) mozgatás
- Torrent áthelyezése (set-location), tracker hozzáadás/törlés
- RSS auto-letöltő, watch-folder, sebesség-grafikon
- Kétnyelvű UI (angol/magyar, választható)

## Licenc

[MIT](LICENSE) © 2026 Viktor Falcsik
