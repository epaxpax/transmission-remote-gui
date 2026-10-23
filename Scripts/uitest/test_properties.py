#!/usr/bin/env python3
"""Batch property editor (#44): right-click a multi-selection → Properties…, mixed values show
as empty "Mixed" fields, and only the fields actually edited reach the daemon — a differing
download limit stays per-torrent, and adding / removing a label keeps every other label.
Labels need Transmission 3.00+, so this runs against both tr3 and tr4."""
import base64, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
T = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
S = "sheet 1 of window 1"
KEY_PROPERTIES = [35, 15, 31, 35, 36]   # type-select "prop" (Properties…), Return
FIELDS = ("id", "name", "downloadLimit", "downloadLimited", "uploadLimited", "peer-limit",
          "bandwidthPriority", "honorsSessionLimits", "labels")
failed = []

def check(name, ok, detail=""):
    print(f"  {'✓' if ok else '✗'} {name}{'' if ok else '  → ' + str(detail)}")
    if not ok:
        failed.append(name)

def add(name):
    p = os.path.join(ui.WORK, f"{name}.torrent")
    ui.make_torrent(p, name=name)
    ui.rpc("torrent-add", metainfo=base64.b64encode(open(p, "rb").read()).decode(), paused=True)

def by_name():
    return {t["name"]: t for t in ui.torrents(FIELDS)}

def find(ident):
    """Whether the sheet has an element with this accessibility identifier."""
    return ui.id_exists(ident, S)

def value(ident):
    return ui.id_value(ident, S)

def type_field(ident, text):
    ui.id_type(ident, text, S)
    time.sleep(0.3)

def open_editor():
    ui.activate()
    # A real click + ⌘A: setting AXSelectedRows does not reach the table's selection model.
    x, y = ui.position(f"UI element 1 of row 1 of {T}")
    ui.left_click(x, y); time.sleep(0.3)
    ui.ax('keystroke "a" using command down'); time.sleep(0.5)
    ui.context_menu_pick(x, y, KEY_PROPERTIES)
    ui.wait_for(lambda: ui.ax(f"exists {S}") == "true", what="properties sheet")
    ui.wait_for(lambda: find("properties.peerLimit"), what="properties loaded")

ui.setup(APP)
try:
    ui.remove_all()
    add("props-alpha"); add("props-beta")
    t = by_name()
    a, b = t["props-alpha"]["id"], t["props-beta"]["id"]
    ui.rpc("torrent-set", ids=[a], downloadLimit=100, downloadLimited=True, labels=["keep", "old"],
           **{"peer-limit": 60})
    ui.rpc("torrent-set", ids=[b], downloadLimit=200, downloadLimited=True, labels=["other"],
           **{"peer-limit": 60})
    before = by_name()

    ui.launch(); ui.assert_isolated(); time.sleep(3)

    # 1. Mixed vs shared values, and Cancel changes nothing.
    open_editor()
    check("differing download limit shows empty (Mixed)", value("properties.downloadLimit") == "",
          value("properties.downloadLimit"))
    check("shared peer limit is prefilled", value("properties.peerLimit") == "60", value("properties.peerLimit"))
    check("Apply disabled while nothing is edited",
          not ui.id_enabled("properties.apply", S))
    type_field("properties.peerLimit", "75")
    ui.id_click("properties.cancel", S); time.sleep(1.5)
    check("Cancel sends nothing", by_name() == before, by_name())

    # 2. Edit the peer limit and labels only.
    open_editor()
    type_field("properties.peerLimit", "75")
    type_field("properties.labelsAdd", "new")
    type_field("properties.labelsRemove", "old")
    ui.id_click("properties.apply", S); time.sleep(2.5)
    after = by_name()
    al, bl = after["props-alpha"], after["props-beta"]
    check("peer limit applied to both", al["peer-limit"] == 75 and bl["peer-limit"] == 75, after)
    check("mixed download limits untouched",
          (al["downloadLimit"], bl["downloadLimit"]) == (100, 200)
          and al["downloadLimited"] and bl["downloadLimited"], after)
    check("unedited flags untouched",
          all(after[n][k] == before[n][k] for n in after for k in ("uploadLimited", "bandwidthPriority",
                                                                    "honorsSessionLimits")), after)
    check("add/remove keeps the other labels",
          al["labels"] == ["keep", "new"] and bl["labels"] == ["other", "new"], (al["labels"], bl["labels"]))
finally:
    ui.remove_all(); ui.teardown()
print(f"\n{'all OK' if not failed else str(len(failed)) + ' failed'}")
sys.exit(1 if failed else 0)
