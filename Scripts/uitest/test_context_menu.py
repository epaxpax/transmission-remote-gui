#!/usr/bin/env python3
"""The row context menu opens on EVERY column, with both right-click and Ctrl+click."""
import base64, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
T = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
SA = T.removeprefix("table 1 of ")
SCREEN_W = float(ui.sh("osascript", "-l", "JavaScript", "-e",
                       'ObjC.import("AppKit"); $.NSScreen.mainScreen.frame.size.width').stdout)
failed = []
ui.setup(APP)
try:
    ui.remove_all()
    p = os.path.join(ui.WORK, "ctx.torrent")
    ui.make_torrent(p, name="context-menu-test")
    ui.rpc("torrent-add", metainfo=base64.b64encode(open(p, "rb").read()).decode(), paused=True)
    ui.launch(); ui.assert_isolated(); time.sleep(3)
    ui.activate(); ui.ax("set size of window 1 to {2400, 700}"); time.sleep(0.5)   # every column visible
    heads = ui.ax(f"get title of every button of group 1 of {T}").split(", ")
    for i in range(1, int(ui.ax(f"count UI elements of row 1 of {T}")) + 1):
        x, y = ui.position(f"UI element {i} of row 1 of {T}")
        if x > SCREEN_W - 20:   # narrower screen (CI runner: 1920 px): scroll the cell into view
            ui.ax(f'set value of (value of attribute "AXHorizontalScrollBar" of {SA}) to 1.0'); time.sleep(0.5)
            x, y = ui.position(f"UI element {i} of row 1 of {T}")
        for ctrl in (False, True):
            ui.activate()
            ui.context_menu_pick(x, y, ui.KEY_MOVE, ctrl=ctrl)
            time.sleep(1.2)
            ok = ui.ax("exists sheet 1 of window 1") == "true"
            name = f"{heads[i - 1]}: {'Ctrl+click' if ctrl else 'right-click'}"
            print(f"  {'✓' if ok else '✗'} {name}")
            if ok:
                ui.click("button 1 of group 1 of sheet 1 of window 1"); time.sleep(0.6)
            else:
                failed.append(name)
    # The test server has no path mappings, so "Show in Finder" must stay out of the menu
    # (and must not leave a double separator behind).
    ui.activate()
    x, y = ui.position(f"UI element 1 of row 1 of {T}")
    items = ui.context_menu_items(x, y).split("|")
    ok = "Show in Finder" not in items and "-|-" not in "|".join(items)
    print(f"  {'✓' if ok else '✗'} no Show in Finder without path mappings")
    if not ok:
        print(f"    {items}"); failed.append("Show in Finder hidden")
finally:
    ui.remove_all(); ui.teardown()
print(f"\n{'all columns OK' if not failed else str(len(failed)) + ' failed'}")
sys.exit(1 if failed else 0)
