#!/usr/bin/env python3
"""Keep the selected detail tab while switching torrents and awaiting delayed metadata.

A loopback mock delays detail reads so the Files empty/loading/content transition is
observable. Tracker editors must reset their target without replacing the selected tab.
"""
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
T = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
TG = "tab group 1 of group 2 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
URL = "https://shared.tabs.invalid/announce"
failed = []

# Query identifiers inside one helper invocation so short loading transitions are observable.
HAS_ID = """on findId(el, ident)
    tell application "System Events"
        try
            if value of attribute "AXIdentifier" of el is ident then return el
        end try
        try
            repeat with child in UI elements of el
                set found to my findId(contents of child, ident)
                if found is not missing value then return found
            end repeat
        end try
    end tell
    return missing value
end findId
on hasId(el, ident)
    return my findId(el, ident) is not missing value
end hasId
"""
hold_details = threading.Event()
release_details = threading.Event()
mutations = []

rows = [
    {"id": ident, "name": f"tab-target-{ident}", "hashString": str(ident) * 40,
     "addedDate": 10 - ident, "status": 0, "totalSize": 100, "sizeWhenDone": 100,
     "leftUntilDone": 100, "percentDone": 0, "downloadDir": "/test", "labels": [],
     "files": [{"name": f"file-{ident}.bin", "length": 100, "bytesCompleted": 0}],
     "fileStats": [{"bytesCompleted": 0, "wanted": True, "priority": 0}], "peers": [],
     "trackers": [{"id": ident * 10, "announce": URL, "tier": 0}],
     "trackerStats": [{"id": ident * 10, "announce": URL, "host": "shared.tabs.invalid", "tier": 0}]}
    for ident in (1, 2, 3)
]
rows[2]["files"] = []
rows[2]["fileStats"] = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        args = request.get("arguments", {})
        method = request["method"]
        result, response = "success", {}
        if method == "torrent-get":
            fields = args.get("fields", [])
            selected = [r for r in rows if "ids" not in args or r["id"] in args["ids"]]
            response = {"torrents": [{k: v for k, v in row.items() if k in fields} for row in selected]}
            if "files" in fields:
                if hold_details.is_set():
                    release_details.wait(timeout=120)
                else:
                    time.sleep(0.8)
        elif method == "session-get":
            response = {"version": "4.0.5", "rpc-version": 17, "download-dir": "/test"}
        elif method == "session-stats":
            response = {"torrentCount": len(rows), "activeTorrentCount": 0, "pausedTorrentCount": len(rows),
                        "downloadSpeed": 0, "uploadSpeed": 0}
        elif method == "free-space":
            response = {"size-bytes": 1000000}
        else:
            mutations.append(request)
            result = "fixture: mutation refused"
        payload = json.dumps({"result": result, "arguments": response}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError):
            pass  # A rapid selection change cancels the previous detail request.


def check(name, ok, detail=""):
    print(f"  {'✓' if ok else '✗'} {name}{'' if ok else ' → ' + str(detail)}", flush=True)
    if not ok:
        failed.append(name)


def choose_tab(name):
    ui.activate()
    ui.click(f'(first radio button of {TG} whose description is "{name}")')
    ui.wait_for(lambda: ui.ax(f'value of (first radio button of {TG} whose description is "{name}")') == "1",
                what=f"selected {name} tab")


def stable_ax(action):
    # A refresh can invalidate an AX reference between lookup and access, as in test_queue.py.
    for attempt in range(5):
        try:
            return action()
        except RuntimeError as error:
            if not any(code in str(error) for code in ("(-1719)", "(-1728)")) or attempt == 4:
                raise
            time.sleep(0.2)


def switch_and_sample(name, target):
    ui.activate()
    # Read the native tab selection in one helper call, during and after the delayed fetch.
    result = stable_ax(lambda: ui.osa(HAS_ID + f'''tell application "System Events" to tell process "{ui.PROCESS}"
repeat with r in rows of {T}
    if value of static text 1 of UI element 1 of r is "tab-target-{target}" then set selected of r to true
end repeat
set samples to {{}}
repeat 20 times
    try
        set currentTab to description of (first radio button of {TG} whose value is 1)
    on error
        set currentTab to "missing"
    end try
    if "{name}" is "Files" then
        set fileList to my findId({TG}, "files.list")
        set listPresent to fileList is not missing value
        set fileRows to 0
        if fileList is not missing value then set fileRows to count rows of fileList
        set end of samples to currentTab & "|" & listPresent & "|" & fileRows
    else
        set end of samples to currentTab
    end if
    delay 0.02
end repeat
set AppleScript's text item delimiters to linefeed
return samples as text
end tell''')).splitlines()
    check(f"{name}: target {target} keeps its tab throughout the detail refresh",
          result and all(value.split("|")[0] == name for value in result), result)
    if name == "Files":
        check(f"Files: target {target} keeps the list background while loading",
              result and all(value.split("|")[1] == "true" for value in result), result)
        check(f"Files: target {target} retains visible rows during loading",
              result and all(int(value.split("|")[2]) > 0 for value in result), result)
        ui.wait_for(lambda: ui.id_exists(f"files.row.file-{target}.bin"), what="new torrent file list")
        check(f"Files: target {target} displays its own files", True)


mock = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=mock.serve_forever, daemon=True).start()
ui.PORT = mock.server_port
ui.RPC = f"http://127.0.0.1:{ui.PORT}/transmission/rpc"
ui.ensure_daemon = lambda: None
try:
    ui.setup(APP)
    ui.defaults("appLanguage", "english")
    ui.launch(); ui.assert_isolated(); ui.activate()
    ui.ax("set size of window 1 to {1650, 800}")
    ui.wait_for(lambda: ui.ax(f"count rows of {T}") == "3", what="fixture torrents")
    ui.ax(f"set selected of row 1 of {T} to true")
    ui.click_toolbar("Details")
    for name in ("General", "Files", "Peers", "Trackers"):
        choose_tab(name)
        switch_and_sample(name, 2)
        switch_and_sample(name, 1)
    choose_tab("Trackers")
    ui.wait_for(lambda: ui.id_exists("trackers.table"), what="tracker editor")
    ui.ax_id("trackers.table", "set selected of row 1 of e to true")
    ui.wait_for(lambda: ui.id_enabled("trackers.remove"), what="selected tracker")
    switch_and_sample("Trackers", 2)
    check("switching torrents clears the previous tracker selection", not ui.id_enabled("trackers.remove"))
    ui.ax(f"set selected of row 1 of {T} to false\nset selected of row 2 of {T} to false")
    time.sleep(0.2)
    ui.ax(f"set selected of row 1 of {T} to true")
    ui.wait_for(lambda: ui.id_exists("trackers.add"), what="restored tracker tab")
    check("Tracker tab survives an empty selection", ui.ax(
        f'value of (first radio button of {TG} whose description is "Trackers")') == "1")
    choose_tab("Files")
    ui.wait_for(lambda: ui.id_exists("files.row.file-1.bin"), what="initial file snapshot")
    hold_details.set()
    ui.ax(f"set selected of row 2 of {T} to true")
    ui.wait_for(lambda: ui.id_exists("files.loading"), what="held detail request")
    check("pending detail keeps the previous file row visible", ui.id_exists("files.row.file-1.bin"))
    check("pending detail disables the previous file checkbox", not ui.id_enabled("files.wanted.file-1.bin"))
    check("pending detail disables the previous file priority", not ui.id_enabled("files.priority.file-1.bin"))
    ui.ax_id("files.wanted.file-1.bin", 'try\nperform action "AXPress" of e\nend try')
    check("disabled stale controls send no mutation", not mutations)
    ui.ax(f"set selected of row 1 of {T} to true\ndelay 0.1\nset selected of row 2 of {T} to true")
    release_details.set()
    hold_details.clear()
    ui.wait_for(lambda: ui.id_exists("files.row.file-2.bin"), what="latest target after rapid switching")
    check("rapid switching ends on the latest torrent files", not ui.id_exists("files.row.file-1.bin"))
    ui.activate()
    ui.ax(f"set selected of row 3 of {T} to true")
    ui.wait_for(lambda: ui.id_exists("files.empty"), what="loaded empty file list")
    check("loaded empty metadata keeps the list background", ui.id_exists("files.list"))
    check("loaded empty metadata ends the loading indicator", not ui.id_exists("files.loading"))
finally:
    if sys.exc_info()[0]:
        try:
            print("Failure PID/windows:", ui.pid(), ui.windows(), flush=True)
            print("Failure AX windows:", ui.ax("return {count windows, name of every window}"), flush=True)
        except Exception as error:
            print("Failure window diagnostic:", error, flush=True)
    release_details.set()
    ui.teardown()
    mock.shutdown()
print(f"\n{len(failed)} failed", flush=True)
sys.exit(bool(failed))
