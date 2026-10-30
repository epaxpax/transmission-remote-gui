#!/usr/bin/env python3
"""Files tab as a folder tree, against a local mock daemon (no Docker):
default-expanded root folder, expand/collapse that survives the periodic refresh,
tri-state folder checkbox and folder priority (each one `torrent-set` with every descendant
index), single-file torrents, and Show in Finder for a file and a folder via a path mapping.

Usage: UITEST_WORK=<temporary directory> python3 Scripts/uitest/test_file_tree.py [app]
"""
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
T = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
TG = "tab group 1 of group 2 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
FILES = ["Show/S01/e01.mkv", "Show/S01/e02.mkv", "Show/Extras/info.nfo", "Show/S01/e03.mkv"]
failed = []


def check(name, ok, detail=""):
    print(f"  {'✓' if ok else '✗'} {name}{'' if ok else '  → ' + str(detail)}", flush=True)
    if not ok:
        failed.append(name)


def exists(identifier):
    return ui.id_exists(identifier)

def value(identifier):
    return ui.id_value(identifier)

def press(identifier):
    ui.id_click(identifier)
    time.sleep(1)

def pick(identifier, title):
    ui.ax_id(identifier, f'''perform action "AXPress" of e
delay 0.5
perform action "AXPress" of menu item "{title}" of menu 1 of e''')
    time.sleep(1.5)

def centre(identifier):
    out = ui.ax_id(identifier, "return {position, size} of e")
    x, y, w, h = (int(float(v)) for v in out.split(", "))
    return x + min(w // 2, 120), y + h // 2

def main():
    work = Path(ui.WORK)
    share = work / "file-tree-share"
    for name in FILES:
        (share / "media" / name).parent.mkdir(parents=True, exist_ok=True)
        (share / "media" / name).write_text("fixture", encoding="utf-8")
    wanted = [True, True, False, True]
    priority = [1, 1, 0, 1]
    rows = [{"id": 1, "name": "Tree fixture", "hashString": "1" * 40, "downloadDir": "/srv/media",
             "addedDate": 99, "status": 0, "percentDone": 0.5, "totalSize": 400, "sizeWhenDone": 400,
             "leftUntilDone": 200, "trackers": [], "trackerStats": [], "peers": [], "labels": []},
            {"id": 2, "name": "Single file fixture", "hashString": "2" * 40, "downloadDir": "/srv/media",
             "addedDate": 98, "status": 0, "percentDone": 1, "totalSize": 7, "sizeWhenDone": 7,
             "leftUntilDone": 0, "files": [{"name": "single.mkv", "length": 7, "bytesCompleted": 7}],
             "fileStats": [{"bytesCompleted": 7, "wanted": True, "priority": 0}],
             "trackers": [], "trackerStats": [], "peers": [], "labels": []}]
    sets = []
    blocked = []

    def tree_row():
        row = dict(rows[0])
        row["files"] = [{"name": n, "length": 100, "bytesCompleted": 50 * (i % 3)} for i, n in enumerate(FILES)]
        row["fileStats"] = [{"bytesCompleted": 50 * (i % 3), "wanted": wanted[i], "priority": priority[i]}
                            for i in range(len(FILES))]
        return row

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *arguments):
            pass

        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            method = request["method"]
            arguments = request.get("arguments", {})
            result, response = "success", {}
            if method == "torrent-get":
                ids = arguments.get("ids")
                current = [tree_row(), rows[1]]
                selected = current if ids is None else [row for row in current if row["id"] in ids]
                response = {"torrents": [{key: value for key, value in row.items()
                             if key in arguments.get("fields", row)} for row in selected]}
            elif method == "torrent-set":
                sets.append(arguments)
                for index in arguments.get("files-wanted", []):
                    wanted[index] = True
                for index in arguments.get("files-unwanted", []):
                    wanted[index] = False
                for key, level in [("priority-low", -1), ("priority-normal", 0), ("priority-high", 1)]:
                    for index in arguments.get(key, []):
                        priority[index] = level
            elif method == "session-get":
                response = {"version": "4.0.5", "rpc-version": 17, "download-dir": "/srv/media"}
            elif method == "session-stats":
                response = {"activeTorrentCount": 0, "pausedTorrentCount": len(rows),
                            "torrentCount": len(rows), "uploadSpeed": 0, "downloadSpeed": 0}
            elif method == "free-space":
                response = {"path": arguments.get("path"), "size-bytes": 1000000000}
            else:
                blocked.append(method)
                result = "fixture: method refused"
            payload = json.dumps({"result": result, "arguments": response, "tag": request.get("tag", 0)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    mock = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=mock.serve_forever, daemon=True).start()
    ui.PORT = mock.server_port
    ui.RPC = f"http://127.0.0.1:{ui.PORT}/transmission/rpc"
    ui.ensure_daemon = lambda: None  # The mock replaces the harness's disposable Docker daemon.
    try:
        ui.setup(APP)
        config_path = Path(ui.HOME) / "Library" / "Application Support" / "Transwift" / "servers.json"
        config = json.loads(config_path.read_text())
        config[0]["pathMappings"] = [{"remotePath": "/srv", "localPath": str(share)}]
        config_path.write_text(json.dumps(config), encoding="utf-8")
        ui.defaults("appLanguage", "english")
        ui.launch(); ui.assert_isolated(); time.sleep(4); ui.activate()
        # AX only lists the List's on-screen rows: a tall window keeps every tree row visible.
        ui.ax("set size of window 1 to {1200, 900}"); time.sleep(1)
        ui.ax(f'set value of attribute "AXSelected" of row 1 of {T} to true'); time.sleep(1)
        ui.click_toolbar("Details"); time.sleep(2)
        ui.click(f'(first radio button of {TG} whose description is "Files")'); time.sleep(2)

        ui.wait_for(lambda: exists("files.row.Show/S01/"), what="the tree's folder rows")
        check("a lone root folder starts expanded", exists("files.row.Show/Extras/"))
        check("nested folders start collapsed", not exists("files.row.Show/S01/e01.mkv"))
        press("files.disclosure.Show/S01/")
        check("expanding a folder shows its files", exists("files.row.Show/S01/e01.mkv"))
        time.sleep(4)   # several detail refreshes
        check("expanded state survives the refresh", exists("files.row.Show/S01/e03.mkv"))

        check("folder checkbox: mixed when partly wanted", value("files.wanted.Show/") in ("2", "-1"),   # mixed: macOS 15 AX reports -1
              value("files.wanted.Show/"))
        check("folder checkbox: on when all wanted", value("files.wanted.Show/S01/") == "1")
        check("folder priority: mixed", value("files.priority.Show/") == "Mixed", value("files.priority.Show/"))
        check("folder priority: uniform", value("files.priority.Show/S01/") == "High",
              value("files.priority.Show/S01/"))

        before = len(sets)
        press("files.wanted.Show/S01/")
        ui.wait_for(lambda: len(sets) > before, what="torrent-set for the folder checkbox")
        time.sleep(1)
        check("folder checkbox: one torrent-set with every descendant",
              len(sets) == before + 1 and sorted(sets[-1].get("files-unwanted", [])) == [0, 1, 3], sets[before:])
        ui.wait_for(lambda: value("files.wanted.Show/") == "0", what="root folder unchecked")

        before = len(sets)
        pick("files.priority.Show/", "Low")
        ui.wait_for(lambda: len(sets) > before, what="torrent-set for the folder priority")
        time.sleep(1)
        check("folder priority: one torrent-set with every descendant",
              len(sets) == before + 1 and sorted(sets[-1].get("priority-low", [])) == [0, 1, 2, 3], sets[before:])
        ui.wait_for(lambda: value("files.priority.Show/S01/") == "Low", what="priority shown on the subfolder")

        for identifier, expected in [("files.row.Show/S01/e01.mkv", share / "media" / "Show/S01/e01.mkv"),
                                     ("files.row.Show/Extras/", share / "media" / "Show/Extras")]:
            x, y = centre(identifier)
            ui.close_finder_windows()
            ui.context_menu_pick(x, y, ui.KEY_SHOW)

            ui.wait_finder_selection(expected)
            check(f"Show in Finder: {identifier}", True)
            ui.activate(); time.sleep(1)

        press("files.disclosure.Show/")
        check("collapsing the root hides everything below", not exists("files.row.Show/S01/"))

        ui.ax(f'set value of attribute "AXSelected" of row 2 of {T} to true'); time.sleep(3)
        ui.wait_for(lambda: exists("files.row.single.mkv"), what="single-file torrent row")
        check("single-file torrent: one file row, no disclosure", not exists("files.disclosure.single.mkv"))
        check("only torrent-get / torrent-set used", not blocked, blocked)
    finally:
        ui.teardown()
        mock.shutdown()
    print(f"\n{'all file tree checks OK' if not failed else str(len(failed)) + ' failed'}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
