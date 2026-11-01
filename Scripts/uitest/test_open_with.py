#!/usr/bin/env python3
"""External torrent opens ask for a destination and submit only after confirmation."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

FIX = os.path.join(ui.WORK, "fixtures")
os.makedirs(FIX, exist_ok=True)
results = []
SHEET = "sheet 1 of window 1"


def check(name, fn):
    try:
        fn()
        results.append((name, None))
        print(f"  ✓ {name}")
    except Exception as e:
        results.append((name, e))
        print(f"  ✗ {name}: {e}")
        try:
            ui.screenshot(os.path.join(ui.WORK, f"fail-{len(results)}.png"))
        except Exception:
            pass
        # Recover the isolated test copy so later cases can still exercise their own opens.
        for _ in range(4):
            if not sheet_open():
                break
            ui.ax('set frontmost to true\nkey code 53')
            time.sleep(0.7)


def hashes():
    return {t["hashString"] for t in ui.torrents()}


def added(h, timeout=20):
    ui.wait_for(lambda: h in hashes(), timeout=timeout, what=f"torrent {h[:8]} on the daemon")


def sheet_open():
    return ui.ax(f"exists {SHEET}") == "true"


def prompt(h):
    ui.wait_for(lambda: sheet_open() and ui.id_enabled("add.submit", SHEET), what="destination confirmation")
    assert h not in hashes(), "torrent was submitted before confirmation"


def confirm(h, folder=None, wait_closed=True):
    prompt(h)
    if folder is not None:
        ui.id_type("add.downloadDir", folder, SHEET)
    ui.id_click("add.submit", SHEET)
    added(h)
    if wait_closed:
        ui.wait_for(lambda: not sheet_open(), what="confirmation sheet to close")
    else:
        time.sleep(1)  # let dismissal finish before interacting with the next queued sheet


def cancelled(path, h):
    ui.launch(path)
    prompt(h)
    ui.ax('set frontmost to true\nkey code 53')
    ui.wait_for(lambda: not sheet_open(), what="cancelled confirmation to close")
    time.sleep(1)
    assert h not in hashes(), "Cancel submitted the torrent"


def no_mapped_picker():
    assert not ui.id_exists("add.downloadDir.mappings", SHEET), "mapped-folder picker shown without mappings"


def one_window():
    time.sleep(1.5)   # give SwiftUI the chance to (wrongly) spawn a window
    n = len(ui.windows())
    assert n == 1, f"expected 1 window, found {n}"


def ignored(path):
    before = len(ui.torrents())
    ui.launch(path)
    time.sleep(2)
    n = len(ui.torrents())
    assert n == before, f"{n - before} torrent(s) added"


ui.setup()
try:
    ui.remove_all()
    ui.defaults("appLanguage", "english")
    print("Open With destination confirmation")
    cold = os.path.join(FIX, "cold.torrent")
    h_cold = ui.make_torrent(cold)
    check("cold launch with a .torrent waits for confirmation", lambda: (ui.launch(cold), prompt(h_cold)))
    check("no mappings hides the mapped-folder picker", no_mapped_picker)
    check("confirming the cold-opened file adds it", lambda: confirm(h_cold))
    check("cold launch leaves exactly one window", one_window)
    check("the copy runs isolated, on the test server", ui.assert_isolated)

    warm = os.path.join(FIX, "warm.torrent")
    h_warm = ui.make_torrent(warm)
    target = ui.rpc("session-get")["download-dir"].rstrip("/") + "/confirmed"
    check("opening a .torrent while running waits, then uses the chosen folder",
          lambda: (ui.launch(warm), confirm(h_warm, target)))
    def chosen_folder():
        rows = [t for t in ui.torrents(("hashString", "downloadDir")) if t["hashString"] == h_warm]
        assert rows[0]["downloadDir"].rstrip("/") == target
        assert ui.rpc("session-get")["download-dir"].rstrip("/") != target, "daemon default changed"
    check("the chosen destination applies only to that torrent", chosen_folder)
    check("…and does not open a second window", one_window)

    h_mag, magnet = ui.make_magnet()
    check("opening a magnet link waits for confirmation", lambda: (ui.launch(magnet), confirm(h_mag)))
    check("…and does not open a second window", one_window)

    multi = [os.path.join(FIX, f"multi{i}.torrent") for i in range(3)]
    h_multi = [ui.make_torrent(p) for p in multi]
    def multiple_opens():
        ui.launch(*multi)
        for i, h in enumerate(h_multi):
            assert not any(other in hashes() for other in h_multi[i:]), "queued torrent added too early"
            confirm(h, wait_closed=i == len(h_multi) - 1)
    check("several files each wait for confirmation in arrival order", multiple_opens)

    cancel_file = os.path.join(FIX, "cancel.torrent")
    h_cancel = ui.make_torrent(cancel_file)
    check("Cancel discards a file without submitting", lambda: cancelled(cancel_file, h_cancel))
    h_cancel_mag, cancel_magnet = ui.make_magnet()
    check("Cancel discards a magnet without submitting", lambda: cancelled(cancel_magnet, h_cancel_mag))

    txt = os.path.join(FIX, "notes.txt")
    open(txt, "w").write("not a torrent")
    check("a non-torrent file is ignored", lambda: ignored(txt))

    ui.screenshot(os.path.join(ui.WORK, "open-with-final.png"))
finally:
    ui.remove_all()
    ui.teardown()

failed = [n for n, e in results if e]
print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if failed else 0)
