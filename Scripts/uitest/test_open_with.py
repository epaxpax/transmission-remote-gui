#!/usr/bin/env python3
"""Issue #5: .torrent files / magnet links opened from outside get added, without extra windows."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

FIX = os.path.join(ui.WORK, "fixtures")
os.makedirs(FIX, exist_ok=True)
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
            ui.screenshot(os.path.join(ui.WORK, f"fail-{len(results)}.png"))
        except Exception:
            pass


def hashes():
    return {t["hashString"] for t in ui.torrents()}


def added(h, timeout=20):
    ui.wait_for(lambda: h in hashes(), timeout=timeout, what=f"torrent {h[:8]} on the daemon")


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
    print("Open With (#5)")
    cold = os.path.join(FIX, "cold.torrent")
    h_cold = ui.make_torrent(cold)
    check("cold launch with a .torrent adds it", lambda: (ui.launch(cold), added(h_cold)))
    check("cold launch leaves exactly one window", one_window)
    check("the copy runs isolated, on the test server", ui.assert_isolated)

    warm = os.path.join(FIX, "warm.torrent")
    h_warm = ui.make_torrent(warm)
    check("opening a .torrent while running adds it", lambda: (ui.launch(warm), added(h_warm)))
    check("…and does not open a second window", one_window)

    h_mag, magnet = ui.make_magnet()
    check("opening a magnet link adds it", lambda: (ui.launch(magnet), added(h_mag)))
    check("…and does not open a second window", one_window)

    multi = [os.path.join(FIX, f"multi{i}.torrent") for i in range(3)]
    h_multi = [ui.make_torrent(p) for p in multi]
    check("opening several .torrent files at once adds all", lambda: (ui.launch(*multi), [added(h) for h in h_multi]))

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
