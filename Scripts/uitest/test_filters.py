#!/usr/bin/env python3
"""Sidebar tracker / folder filters (#16): the sections list every tracker host and download
folder with counts, clicking one narrows the list (combined with the others and the status
filter), clicking it again clears it, and a torrent added while running shows up in them."""
import base64, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
T = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
SIDEBAR = "outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1"
ALPHA, BETA = "http://alpha.uitest.invalid/announce", "http://beta.uitest.invalid/announce"
A, B = "tracker.alpha.uitest.invalid", "tracker.beta.uitest.invalid"
MOV, TV = "folder./downloads/movies", "folder./downloads/tv"
failed = []

def check(name, ok, detail=""):
    print(f"  {'✓' if ok else '✗'} {name}{'' if ok else '  → ' + str(detail)}")
    if not ok:
        failed.append(name)

def add(name, tracker, folder):
    p = os.path.join(ui.WORK, f"{name}.torrent")
    ui.make_torrent(p, name=name, tracker=tracker)
    ui.rpc("torrent-add", metainfo=base64.b64encode(open(p, "rb").read()).decode(), paused=True,
           **{"download-dir": folder})

def sidebar_button(ident):
    """The sidebar row button with this accessibility identifier ("tracker.<host>",
    "folder.<path>", "filter.<status>"). SwiftUI exposes the row's text only as an
    attributed description System Events cannot read, so rows are found by identifier."""
    n = int(ui.ax(f"count rows of {SIDEBAR}"))
    for i in range(1, n + 1):
        elem = f"button 1 of UI element 1 of row {i} of {SIDEBAR}"
        try:
            if ui.ax(f'get value of attribute "AXIdentifier" of {elem}') == "sidebar." + ident:
                return elem
        except RuntimeError:
            pass   # heading rows have no button
    return None

def sidebar_has(ident):
    return sidebar_button(ident) is not None

def tap(ident):
    elem = sidebar_button(ident)
    assert elem, f"no sidebar row '{ident}'"
    ui.click(elem); time.sleep(1)

def shown():
    """Names of the torrents currently in the list. The table reloads on every poll, so a
    row can vanish mid-read — retry instead of failing on that race."""
    for attempt in range(5):
        try:
            n = int(ui.ax(f"count rows of {T}"))
            return sorted(ui.ax(f"get value of static text 1 of UI element 1 of row {i} of {T}")
                          for i in range(1, n + 1))
        except RuntimeError:
            if attempt == 4:
                raise
            time.sleep(0.5)

ui.setup(APP)
ui.defaults("appLanguage", "english")
try:
    ui.remove_all()
    add("f-tv-alpha", ALPHA, "/downloads/tv")
    add("f-mov-beta", BETA, "/downloads/movies")
    add("f-mov-alpha", ALPHA, "/downloads/movies/")   # trailing slash = same folder
    ui.launch(); ui.assert_isolated(); time.sleep(5); ui.activate()

    check("tracker and folder sections listed",
          all(sidebar_has(s) for s in (A, B, MOV, TV)),
          [s for s in (A, B, MOV, TV) if not sidebar_has(s)])
    check("all three shown without a filter", shown() == ["f-mov-alpha", "f-mov-beta", "f-tv-alpha"], shown())

    tap(A)
    check("tracker filter", shown() == ["f-mov-alpha", "f-tv-alpha"], shown())
    tap(MOV)
    check("tracker + folder combine", shown() == ["f-mov-alpha"], shown())
    tap("filter.stopped")
    check("... and combine with the status filter", shown() == ["f-mov-alpha"], shown())
    tap(A)
    check("clicking the tracker again clears it", shown() == ["f-mov-alpha", "f-mov-beta"], shown())
    tap(MOV); tap("filter.all")
    check("folder cleared too", len(shown()) == 3, shown())

    add("f-tv-beta", BETA, "/downloads/tv")   # while running: its tracker comes on the next poll
    ui.wait_for(lambda: len(shown()) == 4, what="the new torrent in the list")
    time.sleep(3)
    tap(B)
    check("a torrent added while running is in the tracker filter", shown() == ["f-mov-beta", "f-tv-beta"], shown())
    tap(B)
finally:
    ui.remove_all(); ui.teardown()
print(f"\n{'all filter checks OK' if not failed else str(len(failed)) + ' failed'}")
sys.exit(1 if failed else 0)
