#!/usr/bin/env python3
"""Set a watch folder in the macOS UI and verify imports against the isolated daemon."""
import json
import os
from pathlib import Path
import sys
import time
from uuid import uuid4

import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
SERVER_FILE = Path(ui.HOME) / "Library/Application Support/Transwift/servers.json"
SETTINGS = 'window "Servers"'
EDIT = f"sheet 1 of {SETTINGS}"
PREFIX = "watch-test-" + uuid4().hex[:8]
FIELDS = ("id", "name", "status", "downloadDir")


def check(condition, message):
    assert condition, message
    print(f"  ✓ {message}", flush=True)


def records():
    return {t["name"]: t for t in ui.torrents(FIELDS) if t["name"].startswith(PREFIX)}


def edit_server():
    ui.activate()
    if ui.ax(f"exists {SETTINGS}") != "true":
        ui.ax('keystroke "," using {command down}')
    servers_tab = 'button "Servers" of toolbar 1 of window 1'
    ui.wait_for(lambda: ui.ax(f"exists {servers_tab}") == "true", what="Settings window")
    ui.ax(f"click {servers_tab}")
    ui.wait_for(lambda: ui.ax(f"exists {SETTINGS}") == "true", what="Servers settings")
    geometry = ui.ax_id("servers.name." + ui.SERVER_ID, "return {position, size} of e", SETTINGS)
    x, y, width, height = (float(v) for v in geometry.split(", "))
    ui.left_click(x + width / 2, y + height / 2)
    ui.ax_id("servers.edit", "click e", SETTINGS)
    ui.wait_for(lambda: ui.ax(f"exists {EDIT}") == "true", what="server editor")
    ui.ax(f'click (first radio button of tab group 1 of group 1 of {EDIT} whose description is "Watch Folder")')
    ui.wait_for(lambda: ui.id_exists("watchFolder.choose", EDIT), what="watch folder tab")


def save():
    geometry = ui.ax_id("server.save", "return {position, size} of e", EDIT)
    x, y, width, height = (float(v) for v in geometry.split(", "))
    ui.left_click(x + width / 2, y + height / 2)
    ui.wait_for(lambda: ui.ax(f"exists {EDIT}") == "false", what="saved server editor")
    ui.ax(f'click (first button of {SETTINGS} whose subrole is "AXCloseButton")')


def paste_path(folder):
    ui.ax_id("watchFolder.path", "set focused of e to true", EDIT)
    # Paste in one edit and restore every clipboard format, even on a desktop with an IME.
    ui.jxa("""ObjC.import("AppKit"); ObjC.import("Foundation");
var board = $.NSPasteboard.generalPasteboard, saved = [];
var items = board.pasteboardItems;
for (var i = 0; i < items.count; i++) {
    var item = items.objectAtIndex(i), copy = $.NSPasteboardItem.alloc.init;
    for (var j = 0; j < item.types.count; j++) {
        var type = item.types.objectAtIndex(j);
        copy.setDataForType(item.dataForType(type), type);
    }
    saved.push(copy);
}
board.clearContents;
board.setStringForType($(""" + json.dumps(str(folder)) + """), $.NSPasteboardTypeString);
var writtenCount = board.changeCount;
try {
    Application("System Events").keystroke("v", {using: ["command down"]});
    $.NSThread.sleepForTimeInterval(0.6);
} finally {
    if (board.changeCount === writtenCount) {
        board.clearContents;
        if (saved.length) board.writeObjects($(saved));
    }
}
""")
    ui.wait_for(lambda: ui.ax_id("watchFolder.path", "return value of e", EDIT) == str(folder),
                what="entered folder path")
    ui.ax("key code 48")  # Leave the field to commit the edit before saving.


def configured_path():
    return json.loads(SERVER_FILE.read_text())[0].get("watchFolderPath")


def fixture(folder, key):
    name = f"{PREFIX}-{key}.bin"
    path = folder / f"{key}.torrent"
    ui.make_torrent(path, name=name)
    return name, path


ui.setup(APP)
ui.defaults("appLanguage", "english")
folder = (Path(ui.WORK) / "Watch").resolve()
folder.mkdir(exist_ok=True)
session = ui.rpc("session-get")
try:
    version = session["version"]
    check(version.startswith("3.00") if ui.DAEMON == "tr3" else version.startswith("4."),
          f"connected to Transmission {version}")
    ui.rpc("session-set", **{"start-added-torrents": False})
    ui.launch()
    ui.assert_isolated()

    name, source = fixture(folder, "first")
    metainfo = source.read_bytes()
    check(configured_path() is None and name not in records(), "watching is off before setup")
    edit_server()
    ui.ax_id("watchFolder.choose", "click e", EDIT)
    ui.wait_for(lambda: ui.ax('exists window "Watch Folder"') == "true", what="folder picker")
    ui.ax_id("CancelButton", "click e", 'window "Watch Folder"')
    ui.wait_for(lambda: ui.ax('exists window "Watch Folder"') == "false", what="closed picker")
    paste_path(folder)
    save()
    check(configured_path() is not None and Path(configured_path()).resolve() == folder,
          "folder configured and saved through Settings")

    marker = source.with_suffix(".torrent.added")
    ui.wait_for(marker.exists, timeout=20, what="first successful import")
    check(marker.read_bytes() == metainfo and not source.exists(), "successful import renames the original")
    imported = records()[name]
    check(imported["downloadDir"] == session["download-dir"], "uses the daemon's default download directory")
    # Transmission 3.00 may verify a newly added torrent before settling at stopped.
    ui.wait_for(lambda: records()[name]["status"] == 0, what="paused after initial verification")
    print("  ✓ respects the daemon's auto-start setting", flush=True)

    # A second copy of the same metainfo is already on the daemon and can be marked safely.
    duplicate = folder / "copy.torrent"
    duplicate.write_bytes(metainfo)
    dupe_marker = duplicate.with_suffix(".torrent.added")
    ui.wait_for(dupe_marker.exists, timeout=20, what="duplicate acknowledged")
    check(list(records()) == [name] and dupe_marker.read_bytes() == metainfo,
          "duplicate metainfo is marked without creating another torrent")

    ui.quit_app()
    later_name, later = fixture(folder, "relaunch")
    time.sleep(3)
    check(later.exists() and later_name not in records(), "no imports while the app is closed")
    bad = folder / "invalid.torrent"
    bad.write_bytes(b"not a torrent")
    ui.launch()
    ui.assert_isolated()
    ui.wait_for(later.with_suffix(".torrent.added").exists, timeout=20, what="import after relaunch")
    check(set(records()) == {name, later_name}, "saved folder resumes on launch and skips marked files")
    check(bad.exists() and not bad.with_suffix(".torrent.added").exists(), "rejected input stays intact")

    edit_server()
    ui.ax_id("watchFolder.clear", "click e", EDIT)
    save()
    disabled_name, disabled = fixture(folder, "disabled")
    time.sleep(5)
    check(configured_path() is None and disabled.exists() and disabled_name not in records(),
          "removing the folder in Settings stops automatic imports")
finally:
    ui.quit_app()
    ids = [torrent["id"] for torrent in records().values()]
    if ids:
        ui.rpc("torrent-remove", ids=ids, **{"delete-local-data": True})
    ui.rpc("session-set", **{"start-added-torrents": session["start-added-torrents"]})
    ui.teardown()

print("Watch folder UI tests passed.", flush=True)
