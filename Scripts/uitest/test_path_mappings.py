#!/usr/bin/env python3
"""Read-only Finder integration fixtures; no Docker, NAS or production app writes.

Usage: UITEST_WORK=<temporary directory> python3 Scripts/uitest/test_path_mappings.py [app] [--interactive]
Interactive mode keeps the isolated mock/app alive for settings and error-case inspection.
"""
import argparse
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import trgui_uitest as ui


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", nargs="?", default=os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app"))
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args()
    work = Path(ui.WORK)
    share = work / "mounted-fixture"
    folder = share / "电视剧" / "Finder folder fixture"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "episode 01.txt").write_text("fixture", encoding="utf-8")
    (folder / "episode 02.txt").write_text("fixture", encoding="utf-8")
    movie = share / "电影" / "中文 #100% = 'quoted'.txt"
    movie.parent.mkdir(parents=True, exist_ok=True)
    movie.write_text("fixture", encoding="utf-8")
    rows = []
    cases = [("Finder folder fixture", "/srv/电视剧", ["Finder folder fixture/episode 01.txt", "Finder folder fixture/episode 02.txt"]),
             ("Finder single file fixture", "/srv/电影", [movie.name]),
             ("Finder missing metadata fixture", "/srv/电影", []),
             ("Finder missing file fixture", "/srv/电影", ["missing.txt"])]
    for number, (name, directory, paths) in enumerate(cases, 1):
        rows.append({"id": number, "name": name, "hashString": str(number) * 40,
                     "downloadDir": directory, "addedDate": 100 - number, "status": 0,
                     "percentDone": 1, "totalSize": 14, "sizeWhenDone": 14, "leftUntilDone": 0,
                     "files": [{"name": path, "length": 7, "bytesCompleted": 7} for path in paths],
                     "trackers": [], "trackerStats": [], "peers": [], "labels": []})
    methods = []
    blocked = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *arguments):
            pass

        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            method = request["method"]
            methods.append(method)
            arguments = request.get("arguments", {})
            result = "success"
            if method == "torrent-get":
                ids = arguments.get("ids")
                selected = rows if ids is None else [row for row in rows if row["id"] in ids]
                response = {"torrents": [{key: value for key, value in row.items()
                             if key in arguments.get("fields", row)} for row in selected]}
            elif method == "session-get":
                response = {"version": "4.0.5", "rpc-version": 17, "download-dir": "/srv/电影"}
            elif method == "session-stats":
                response = {"activeTorrentCount": 0, "pausedTorrentCount": len(rows),
                            "torrentCount": len(rows), "uploadSpeed": 0, "downloadSpeed": 0}
            elif method == "free-space":
                response = {"path": arguments.get("path"), "size-bytes": 1000000000}
            else:
                blocked.append(method)
                result, response = "read-only fixture: method refused", {}
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
    ui.ensure_daemon = lambda: None  # This fixture replaces the harness's disposable Docker daemon.
    try:
        ui.setup(args.app)
        config_path = Path(ui.HOME) / "Library" / "Application Support" / "Transwift" / "servers.json"
        config = json.loads(config_path.read_text())
        config[0]["pathMappings"] = [{"remotePath": "/srv", "localPath": str(share)}]
        config_path.write_text(json.dumps(config), encoding="utf-8")
        ui.defaults("appLanguage", "english")
        ui.launch()
        ui.assert_isolated()
        ui.wait_for(lambda: len(methods) >= 3, what="mock polling")
        print(json.dumps({"ready": True, "app": ui.APP, "home": ui.HOME,
                          "folder": str(folder), "file": str(movie)}, ensure_ascii=False), flush=True)
        if args.interactive:
            while True:
                time.sleep(1)
        else:
            table = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
            ui.activate()
            for row, expected in [(1, folder), (2, movie)]:
                x, y = ui.position(f"UI element 1 of row {row} of {table}")
                ui.context_menu_pick(x, y, "Show in Finder")
                selected = lambda: ui.osa('tell application "Finder" to get POSIX path of (item 1 of (get selection) as alias)')
                ui.wait_for(lambda: selected().rstrip("/") == str(expected), what="Finder selection")
                print(f"PASS: Finder {'folder' if row == 1 else 'Unicode single file'}", flush=True)
            assert not blocked, f"unexpected mutating RPC methods: {blocked}"
            print("PASS: only read-only RPC methods used", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        ui.teardown()
        mock.shutdown()
        print(json.dumps({"readOnly": not blocked, "methods": sorted(set(methods))}), flush=True)


if __name__ == "__main__":
    main()
