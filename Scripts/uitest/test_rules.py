#!/usr/bin/env python3
"""Rule engine UI test — automates docs/superpowers/notes/rule-engine-teszt-checklist.md.

Usage: test_rules.py <path to built .app>
"""
import base64, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP_SRC = sys.argv[1]
SHOTS = os.path.join(ui.WORK, "rules-shots")
os.makedirs(SHOTS, exist_ok=True)
FIX = os.path.join(ui.WORK, "fx-rules")
os.makedirs(FIX, exist_ok=True)
results = []

W = "window 1"
RS = f"sheet 1 of {W}"          # Rules sheet
RG = f"group 1 of {RS}"
ES = f"sheet 1 of {RS}"         # rule editor (on top of the Rules sheet)
EG = f"group 1 of {ES}"
LIST = f"outline 1 of scroll area 1 of {RG}"
TABLE = f"table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of {W}"
# Rules sheet buttons (no AX titles in SwiftUI here → by position)
NEW, EDIT, DELETE, UP, DOWN, RUN_NOW, DONE = (f"button {i} of {RG}" for i in range(1, 8))
# Editor: text fields 1 name, 2 condition value, 3 ratio, 4 idle, 5 up, 6 down, 7 label
#         checkboxes 1 enabled, 2 ratio, 3 idle, 4 up, 5 down, 6 label, 7 stop
PREVIEW, CANCEL, SAVE = (f"button {i} of {EG}" for i in range(1, 4))


def check(name, fn):
    try:
        fn()
        results.append((name, None))
        print(f"  ✓ {name}")
    except Exception as e:
        results.append((name, e))
        print(f"  ✗ {name}: {e}")
        try:
            ui.screenshot(os.path.join(SHOTS, f"fail-{len(results):02d}.png"))
            back_to_rules()
        except Exception:
            pass


def back_to_rules():
    """After a failure: Escape out of editor / dry-run sheets so the next check starts clean."""
    for _ in range(4):
        if not exists(ES):
            return
        ui.ax('set frontmost to true\nkey code 53')
        time.sleep(0.6)


def val(path):
    return ui.ax(f"get value of {path}")


def enabled(path):
    return ui.ax(f"get enabled of {path}") == "true"


def exists(path):
    return ui.ax(f"exists {path}") == "true"


def texts(path):
    """All static-text values under `path` (recursive), as one list."""
    out = ui.osa(f'''
on walk(e)
    set acc to {{}}
    tell application "System Events"
        try
            if (class of e) is static text then set end of acc to (value of e) as text
        end try
        set kids to {{}}
        try
            set kids to UI elements of e
        end try
    end tell
    repeat with k in kids
        set acc to acc & my walk(contents of k)
    end repeat
    return acc
end walk
tell application "System Events" to set root to {path} of process "{ui.PROCESS}"
set AppleScript's text item delimiters to linefeed
return (walk(root)) as text''')
    return [l for l in out.split("\n") if l]


def dry_run_sheet():
    """AX path of the open 'What would change' sheet, or None."""
    for p in (f"sheet 1 of {ES}", ES, RS):
        if exists(p) and any("What would change" in t for t in texts(p)[:2]):
            return p
    return None


def wait_dry_run(timeout=10):
    return ui.wait_for(dry_run_sheet, timeout=timeout, what="the 'What would change' sheet")


def dry_run_close(apply=False):
    p = dry_run_sheet()
    ui.click(f"button {2 if apply else 1} of group 1 of {p}")
    ui.wait_for(lambda: dry_run_sheet() is None, what="dry-run sheet to close")


def open_rules():
    ui.activate()
    if not exists(RS):
        ui.click_toolbar("Rules")
        ui.wait_for(lambda: exists(RS), what="Rules sheet")


def close_rules():
    if exists(RS):
        ui.click(DONE)
        ui.wait_for(lambda: not exists(RS), what="Rules sheet to close")


def new_rule(name, value, ratio=None, idle=None, stop=False, enabled_=True, kind=None):
    """Opens the editor and fills it; does NOT save."""
    ui.click(NEW)
    ui.wait_for(lambda: exists(ES), what="rule editor")
    ui.type_into(f"text field 1 of {EG}", name)
    if kind:
        ui.ax(f'click pop up button 1 of {EG}')
        ui.ax(f'click menu item "{kind}" of menu 1 of pop up button 1 of {EG}')
    ui.type_into(f"text field 2 of {EG}", value)
    if ratio is not None:
        ui.click(f"checkbox 2 of {EG}")
        ui.type_into(f"text field 3 of {EG}", ratio)
    if idle is not None:
        ui.click(f"checkbox 3 of {EG}")
        ui.type_into(f"text field 4 of {EG}", idle)
    if stop:
        ui.click(f"checkbox 7 of {EG}")
    if not enabled_:
        ui.click(f"checkbox 1 of {EG}")
    time.sleep(0.3)


def rule_rows():
    return texts(LIST)


def delete_all_rules():
    while ui.ax(f"count rows of {LIST}") != "0":
        ui.ax(f"select row 1 of {LIST}")
        ui.click(DELETE)
        time.sleep(0.6)


def tor(name, fields=("name", "seedRatioLimit", "seedRatioMode", "status", "labels")):
    return next(t for t in ui.torrents(fields) if t["name"] == name)


def add_fixture(name, tracker, paused=True):
    path = os.path.join(FIX, name + ".torrent")
    ui.make_torrent(path, name=name, tracker=tracker)
    ui.rpc("torrent-add", metainfo=base64.b64encode(open(path, "rb").read()).decode(), paused=paused)


def shot(tag):
    ui.screenshot(os.path.join(SHOTS, f"{tag}.png"))


# ------------------------------------------------------------------ run

ui.setup(APP_SRC)
try:
    ui.remove_all()
    for n, tr in [("ubuntu-a.iso", "http://tracker.alpha.test/announce"),
                  ("ubuntu-b.iso", "http://tracker.alpha.test/announce"),
                  ("movie-c.mkv", "http://tracker.beta.test/announce")]:
        add_fixture(n, tr, paused=False)
    ui.launch()
    ui.assert_isolated()
    ui.wait_for(lambda: len(texts(f"{W}")) > 3, what="torrent list")
    open_rules()

    print("A. Saving a new rule offers the dry run")
    def a1():
        new_rule("Alpha ratio", "tracker.alpha.test", ratio="1,5")
        ui.click(SAVE)
        p = wait_dry_run()
        t = texts(p)
        shot("A1-dry-run")
        assert "ubuntu-a.iso" in t and "ubuntu-b.iso" in t, t
        assert "movie-c.mkv" not in t, t
        dry_run_close(apply=True)
        ui.wait_for(lambda: tor("ubuntu-a.iso")["seedRatioLimit"] == 1.5, what="ratio 1.5 on ubuntu-a")
        assert tor("ubuntu-a.iso")["seedRatioMode"] == 1
        assert tor("movie-c.mkv")["seedRatioMode"] == 0
    check("1. new rule → dry run pops up; Apply sets ratio 1.5 (mode 1) only on matches", a1)
    check("10. '1,5' with a comma is accepted", lambda: None if tor("ubuntu-b.iso")["seedRatioLimit"] == 1.5 else 1 / 0)

    print("C. Applied once")
    def c5():
        ui.click(RUN_NOW)
        p = wait_dry_run()
        t = texts(p)
        assert any("Nothing would change" in x for x in t), t
        dry_run_close()
    check("5. running again changes nothing (idempotent)", c5)

    def c6():
        ui.rpc("torrent-set", ids=[t["id"] for t in ui.torrents(("id", "name")) if t["name"] == "ubuntu-a.iso"],
               seedRatioLimit=3.0, seedRatioMode=1)
        ui.click(f"checkbox 1 of {RG}")                     # main switch ON → background runs
        ui.wait_for(lambda: val(f"checkbox 1 of {RG}") == "1", what="engine switch on")
        add_fixture("ubuntu-new.iso", "http://tracker.alpha.test/announce")
        ui.wait_for(lambda: tor("ubuntu-new.iso")["seedRatioLimit"] == 1.5, timeout=20,
                    what="background run to classify the NEW torrent")
        time.sleep(3)                                        # a few more passes
        assert tor("ubuntu-a.iso")["seedRatioLimit"] == 3.0, tor("ubuntu-a.iso")
    check("6. background run handles a new torrent but does NOT overwrite a manual change", c6)

    print("D. Silent failures")
    def d7():
        new_rule("Beta disabled", "tracker.beta.test", ratio="4", enabled_=False)
        ui.click(SAVE)
        ui.wait_for(lambda: not exists(ES), what="editor to close")
        time.sleep(1.5)
        assert dry_run_sheet() is None, "dry run was offered for a disabled rule"
    check("7. saving a DISABLED rule offers no dry run", d7)

    def d8():
        ui.ax(f"select row 2 of {LIST}")
        time.sleep(0.3)
        ui.click(EDIT)
        ui.wait_for(lambda: exists(ES), what="editor")
        name = val(f"text field 1 of {EG}")
        assert name == "Beta disabled", f"editor opened '{name}' (rows: {rule_rows()})"
        ui.click(PREVIEW)
        p = wait_dry_run()
        t = texts(p)
        shot("D8-disabled-preview")
        assert "movie-c.mkv" in t, t
        dry_run_close()
    check("8. 'What would change?' on a disabled rule still shows what it would do", d8)

    def d9():
        ui.type_into(f"text field 3 of {EG}", "abc")
        time.sleep(0.3)
        assert not enabled(SAVE), "Save is enabled with a letter in the ratio field"
        ui.type_into(f"text field 3 of {EG}", "4")
        time.sleep(0.3)
        assert enabled(SAVE)
        ui.click(CANCEL)
        ui.wait_for(lambda: not exists(ES), what="editor to close")
    check("9. a letter in a ticked number field disables Save", d9)

    def d11():
        ui.click(f"checkbox 1 of UI element 1 of row 1 of {LIST}")   # disable rule 1 too
        time.sleep(0.5)
        assert not enabled(RUN_NOW), "Run now is enabled with every rule disabled"
        ui.click(f"checkbox 1 of UI element 1 of row 1 of {LIST}")
        time.sleep(0.5)
        assert enabled(RUN_NOW)
    check("11. every rule disabled → Run now is disabled", d11)

    def d12():
        ui.click(f"checkbox 1 of {RG}")                     # main switch OFF
        time.sleep(0.5)
        t = texts(RG)
        assert any("switched off" in x for x in t), t
        ui.click(f"checkbox 1 of {RG}")
    check("12. main switch off with rules → warning row", d12)

    print("E. Order and language")
    def e13():
        delete_all_rules()
        assert rule_rows() == [], rule_rows()
        new_rule("First 1.1", "ubuntu", ratio="1.1", kind="name pattern")
        ui.click(SAVE); wait_dry_run(); dry_run_close()
        new_rule("Second 2.2", "ubuntu", ratio="2.2", kind="name pattern")
        ui.click(SAVE)
        p = wait_dry_run()
        t = texts(p)
        shot("E13-order")
        dry_run_close()
        ui.click(RUN_NOW)
        p = wait_dry_run()
        t = texts(p)
        assert "First 1.1" in t and "Second 2.2" not in t, t
        dry_run_close()
        # drag the second rule above the first → it must win now
        x1, y1 = ui.position(f"row 2 of {LIST}")
        x0, y0 = ui.position(f"row 1 of {LIST}")
        h = float(ui.ax(f"get size of row 1 of {LIST}").split(", ")[1])
        ui.activate()
        ui.drag(x1, y1, x0, y0 - h / 2 + 2)
        ui.wait_for(lambda: rule_rows()[:1] == ["Second 2.2"], what="rule order to flip")
        ui.click(RUN_NOW)
        p = wait_dry_run()
        t = texts(p)
        shot("E13-order-flipped")
        assert "Second 2.2" in t and "First 1.1" not in t, t
        dry_run_close()
    check("13. two overlapping rules → the FIRST wins; dragging the second up flips it", e13)

    def e13b():
        # rows: [Second, First] after the drag. Keyboard/VoiceOver path: the ▲/▼ buttons.
        assert ui.ax(f"get help of {UP}") == "Move up", ui.ax(f"get help of {UP}")
        ui.ax(f"select row 1 of {LIST}")
        time.sleep(0.3)
        assert not enabled(UP), "Move up is enabled on the first rule"
        ui.click(DOWN)
        ui.wait_for(lambda: rule_rows()[:1] == ["First 1.1"], what="Move down to reorder")
        ui.click(RUN_NOW)
        p = wait_dry_run()
        t = texts(p)
        assert "First 1.1" in t and "Second 2.2" not in t, t
        dry_run_close()
    check("13b. the Move up / Move down buttons reorder too (no drag needed)", e13b)

    def e14():
        delete_all_rules()
        new_rule("Stopper", "movie", stop=True, kind="name pattern")
        ui.click(SAVE)
        p = wait_dry_run()
        t = texts(p)
        shot("E14-stop-english")
        assert any("stop" in x.lower() for x in t) and not any("leállít" in x.lower() for x in t), t
        dry_run_close()
    check("14. English UI: the 'stopped' dry-run line is English", e14)

    close_rules()

    print("F. Context menu regression (v0.1.5)")
    MS = RS                                  # the Move sheet sits where the Rules sheet was
    MG = f"group 1 of {MS}"

    def open_move(ctrl=False):
        x, y = ui.position(f"row 1 of {TABLE}")
        ui.activate()
        ui.context_menu_pick(x - 200, y, ui.KEY_MOVE, ctrl=ctrl)
        ui.wait_for(lambda: exists(MS) and "Move torrent" in texts(MS), timeout=5,
                    what="the Move sheet opened from the context menu")

    def f15(ctrl):
        open_move(ctrl)
        ui.click(f"button 1 of {MG}")        # Cancel
        ui.wait_for(lambda: not exists(MS), what="Move sheet to close")
    check("15a. right-click on a torrent row → context menu (→ Move…)", lambda: f15(False))
    check("15b. Ctrl+click on a torrent row → context menu (→ Move…)", lambda: f15(True))

    def f16():
        rows = ui.ax(f"count rows of {TABLE}")
        open_move()
        ui.type_into(f"text field 1 of {MG}", "D:/media")   # passes the app, the Linux daemon rejects it
        ui.click(f"button 2 of {MG}")
        ui.wait_for(lambda: exists(MS) and "The action failed" in texts(MS), what="the error alert")
        shot("F16-alert")
        assert ui.ax(f"count rows of {TABLE}") == rows, "the torrent list changed"
        ui.click(f"button 1 of {MS}")        # the alert's OK (an alert has no group)
        ui.wait_for(lambda: not exists(MS), what="alert to close")
        assert ui.ax(f"count rows of {TABLE}") == rows, "the list emptied after the alert"
    check("16. Move to a folder the daemon rejects → alert, list is NOT emptied", f16)
finally:
    ui.remove_all()
    ui.teardown()

failed = [n for n, e in results if e]
print(f"\n{len(results) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if failed else 0)
