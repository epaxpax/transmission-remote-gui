#!/usr/bin/env python3
"""Torrent list columns (#15): the header's right-click menu shows/hides columns, the choice
survives a relaunch, and "Default Columns" restores the original set.

The column state is read from the table's autosave in UserDefaults (what AppKit persists),
not from the AX header buttons: those are refreshed lazily and can report a stale set."""
import base64, os, plistlib, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
T = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
SCROLL = "scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
DEFAULT = ["name", "status", "progress", "size", "down", "up", "eta", "ratio", "peers", "added", "activity"]
MENU = ["Name", "Status", "Done", "Size", "Download speed", "Upload speed", "ETA", "Ratio", "Peers", "Added",
        "Last activity", "Completed on", "Remaining", "Downloaded", "Uploaded", "Download folder", "Seeds", "Leechers", "Tracker", "Labels",
        "-", "Default Columns"]
KEY_REMAINING = [15, 14, 46, 36]   # type-select "rem", Return
KEY_DEFAULTS = [2, 14, 3, 36]      # type-select "def", Return
WIDTH = 1650                       # the default columns just fit; one more column does not
failed = []

def check(name, ok, detail=""):
    print(f"  {'✓' if ok else '✗'} {name}{'' if ok else '  → ' + str(detail)}")
    if not ok:
        failed.append(name)

def saved_columns():
    """[(identifier, width, hidden)] from the NSKeyedArchiver blob AppKit autosaves."""
    prefs = plistlib.loads(ui.sh("defaults", "export", ui.BUNDLE_ID, "-").stdout.encode())
    raw = prefs.get("NSTableView Columns v3 TorrentTable")
    if not raw:
        return []
    objs = plistlib.loads(raw)["$objects"]
    out = []
    for ref in objs[1]["NS.objects"]:
        d = objs[ref.data]
        vals = dict(zip((objs[k.data] for k in d["NS.keys"]), (objs[v.data] for v in d["NS.objects"])))
        out.append((vals["Identifier"], vals["Width"], vals["Hidden"]))
    return out

def visible():
    return [c for c, _, hidden in saved_columns() if not hidden]

def overflow():
    tw = float(ui.ax(f"get item 1 of (get size of {T})"))
    sw = float(ui.ax(f"get item 1 of (get size of {SCROLL})"))
    return tw - sw

def header_menu(keys):
    ui.activate()
    x, y = ui.position(f"button 2 of group 1 of {T}")   # the Status header
    ui.context_menu_pick(x, y, keys)
    time.sleep(1.5)

def start():
    ui.launch(); ui.assert_isolated(); time.sleep(4)
    ui.activate(); ui.ax(f"set size of window 1 to {{{WIDTH}, 700}}"); time.sleep(1)

ui.setup(APP)
ui.defaults("appLanguage", "english")
try:
    ui.remove_all()
    p = os.path.join(ui.WORK, "cols.torrent")
    ui.make_torrent(p, name="columns-test")
    ui.rpc("torrent-add", metainfo=base64.b64encode(open(p, "rb").read()).decode(), paused=True)
    start()

    check("default columns", visible() == DEFAULT, visible())
    check("defaults fit without horizontal scroll", overflow() <= 1, overflow())

    ui.activate()
    x, y = ui.position(f"button 2 of group 1 of {T}")
    items = ui.context_menu_items(x, y, shot_path=os.path.join(ui.WORK, "columns-menu.png")).split("|")
    # The header menu is not a top-level AXMenu on every macOS; the screenshot is the fallback.
    if items != [""]:
        check("header menu lists every column + Default Columns", items == MENU, items)
    time.sleep(1)   # let the Esc-closed menu finish tracking before the next one opens

    header_menu(KEY_REMAINING)
    check("'Remaining' shown after toggling", visible() == DEFAULT + ["remaining"], visible())
    check("name column shrinks instead of a horizontal scroll", overflow() <= 1, overflow())

    ui.quit_app(); start()
    check("column choice survives relaunch", visible() == DEFAULT + ["remaining"], visible())

    header_menu(KEY_DEFAULTS)
    check("'Default Columns' restores the original set", visible() == DEFAULT, visible())
    check("no horizontal scroll after reset", overflow() <= 1, overflow())
finally:
    ui.remove_all(); ui.teardown()
print(f"\n{'all column checks OK' if not failed else str(len(failed)) + ' failed'}")
sys.exit(1 if failed else 0)
