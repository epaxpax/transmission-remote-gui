#!/usr/bin/env python3
"""Issue #44: download folder in the Add dialog — per-torrent only, with favorites and history.

Checks against the throw-away daemon that the chosen folder lands on that torrent alone (the
daemon's default stays untouched), that the field defaults to the daemon's folder, that used
folders and favorites are stored per server, and that a relative path is refused.
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

SHEET = "sheet 1 of window 1"
STORE = os.path.join(ui.HOME, "Library", "Application Support", "Transwift", "download-dirs.json")
ALT = "/downloads/uitest-alt"
FAV = "/downloads/uitest-fav"
results = []


def check(name, fn):
    try:
        fn()
        results.append((name, None))
        print(f"  ✓ {name}")
    except Exception as e:
        results.append((name, e))
        print(f"  ✗ {name}: {e}")
        try:
            ui.screenshot(os.path.join(ui.WORK, f"add-dir-fail-{len(results)}.png"))
            close_sheet()
        except Exception:
            pass




def exists(path):
    return ui.ax(f"exists {path}") == "true"


def sheet_open():
    return exists(SHEET)


def open_sheet():
    if not sheet_open():
        ui.click_toolbar("Add")
        ui.wait_for(sheet_open, what="Add sheet")
    time.sleep(0.5)


def close_sheet():
    for _ in range(3):
        if not sheet_open():
            return
        ui.ax('set frontmost to true\nkey code 53')
        time.sleep(0.6)


def field_value():
    return ui.id_value("add.downloadDir", SHEET)

def store():
    try:
        with open(STORE, encoding="utf-8") as f:
            return json.load(f).get(ui.SERVER_ID, {})
    except FileNotFoundError:
        return {}


def torrent_dir(h):
    rows = [t for t in ui.torrents(("hashString", "downloadDir")) if t["hashString"] == h]
    return rows[0]["downloadDir"] if rows else None


def add_magnet(name, folder=None):
    h, magnet = ui.make_magnet(name)
    open_sheet()
    ui.id_type("add.magnet", magnet, SHEET)
    if folder is not None:
        ui.id_type("add.downloadDir", folder, SHEET)
    ui.id_click("add.submit", SHEET)
    ui.wait_for(lambda: torrent_dir(h) is not None, what=f"torrent {name} on the daemon")
    ui.wait_for(lambda: not sheet_open(), what="Add sheet to close")
    return h


ui.setup()
try:
    ui.remove_all()
    ui.defaults("appLanguage", "english")
    ui.launch()
    ui.assert_isolated()
    ui.wait_for(lambda: ui.ax("count windows") != "0", what="the window in AX")
    ui.wait_for(lambda: ui.ax('get enabled of (first button of toolbar 1 of window 1 whose description is "Add")') == "true",
                what="connection (Add enabled)")
    default_dir = ui.rpc("session-get")["download-dir"].rstrip("/")
    print(f"Add dialog download folder (#44) — daemon default {default_dir}")

    def defaults_to_daemon_dir():
        open_sheet()
        ui.wait_for(lambda: field_value().rstrip("/") == default_dir, what="field prefilled with the default")
        close_sheet()
    check("the folder field defaults to the daemon's download-dir", defaults_to_daemon_dir)

    def chosen_folder_used():
        h = add_magnet("uitest-alt-dir", ALT)
        assert torrent_dir(h).rstrip("/") == ALT, f"downloadDir = {torrent_dir(h)}"
        now = ui.rpc("session-get")["download-dir"].rstrip("/")
        assert now == default_dir, f"daemon default changed to {now}"
    check("a chosen folder is sent for that torrent only", chosen_folder_used)

    def recorded_in_history():
        ui.wait_for(lambda: ALT in store().get("recent", []), what="history entry in download-dirs.json")
    check("the used folder is stored in the server's history", recorded_in_history)

    def default_untouched():
        h = add_magnet("uitest-default-dir")
        assert torrent_dir(h).rstrip("/") == default_dir, f"downloadDir = {torrent_dir(h)}"
        assert store().get("recent", [None])[0] == ALT, "the default folder must not enter the history"
    check("leaving the default adds into the daemon's folder", default_untouched)

    def favorite_toggle():
        open_sheet()
        ui.id_type("add.downloadDir", FAV, SHEET)
        ui.id_click("add.downloadDir.favorite", SHEET)
        ui.wait_for(lambda: FAV in store().get("favorites", []), what="favorite saved")
        ui.id_click("add.downloadDir.favorite", SHEET)
        ui.wait_for(lambda: FAV not in store().get("favorites", []), what="favorite removed")
        ui.id_click("add.downloadDir.favorite", SHEET)
        ui.wait_for(lambda: FAV in store().get("favorites", []), what="favorite saved again")
        close_sheet()
    check("the star adds / removes the folder as a favorite", favorite_toggle)

    def relative_refused():
        open_sheet()
        ui.id_type("add.magnet", ui.make_magnet("uitest-relative")[1], SHEET)
        ui.id_type("add.downloadDir", "relative/folder", SHEET)
        ui.wait_for(lambda: ui.id_exists("add.downloadDir.error", SHEET), what="error hint")
        assert not ui.id_enabled("add.submit", SHEET), "Add stays enabled"
        close_sheet()
    check("a relative path disables Add", relative_refused)

    ui.screenshot(os.path.join(ui.WORK, "add-download-dir-final.png"))
finally:
    ui.remove_all()
    ui.teardown()

failed = [n for n, e in results if e]
print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if failed else 0)
