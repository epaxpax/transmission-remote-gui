#!/usr/bin/env python3
"""Download queue controls (#44): run with UITEST_DAEMON=tr3 and tr4.

Only the harness's disposable local daemon is touched. A loopback recording proxy observes
the APP's requests; fixture setup and assertions talk directly to the test daemon.
"""
import base64
import http.client
import http.server
import json
import os
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
T = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
FIELDS = ("id", "name", "queuePosition", "status", "downloadDir", "labels", "bandwidthPriority")
KEYS = {
    "top": [46, 31, 9, 14, 49, 17, 31, 49, 17, 31, 35, 36],  # Move to Top
    "up": [46, 31, 9, 14, 49, 32, 35, 36],                    # Move Up
    "down": [46, 31, 9, 14, 49, 2, 31, 13, 45, 36],          # Move Down
    "bottom": [46, 31, 9, 14, 49, 17, 31, 49, 11, 31, 17, 17, 31, 46, 36],
}
calls = []
lock = threading.Lock()
failed = []


class RecordingProxy(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        request = json.loads(body)
        connection = http.client.HTTPConnection("127.0.0.1", ui.PORT, timeout=10)
        try:
            connection.request("POST", "/transmission/rpc", body, {
                "Content-Type": "application/json",
                "X-Transmission-Session-Id": self.headers.get("X-Transmission-Session-Id", ""),
            })
            response = connection.getresponse()
            data = response.read()
            # Count accepted requests, not the session handshake retry.
            if response.status == 200 and request["method"].startswith("queue-move-"):
                with lock:
                    calls.append(request)
            self.send_response(response.status)
            session = response.getheader("X-Transmission-Session-Id")
            if session:
                self.send_header("X-Transmission-Session-Id", session)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        finally:
            connection.close()

    def log_message(self, *_):
        pass


def check(name, ok, detail=""):
    print(f"  {'✓' if ok else '✗'} {name}{'' if ok else ' → ' + str(detail)}", flush=True)
    if not ok:
        failed.append(name)


def state():
    return {t["id"]: t for t in ui.torrents(FIELDS)}


def order():
    return [t["id"] for t in sorted(state().values(), key=lambda t: t["queuePosition"])]


def shown():
    return read_column(1)

def ready(action):
    """Polling can replace AX objects between a lookup and an action."""
    last = None
    for attempt in range(5):
        try:
            return action()
        except RuntimeError as error:
            if "(-1719)" not in str(error) and "no element with identifier" not in str(error):
                raise
            last = error
            time.sleep(0.5)
    raise last


def read_column(column):
    """Read a whole snapshot in one helper invocation, not one per cell."""
    for attempt in range(5):
        try:
            text = ui.ax(f"""set values to {{}}
repeat with r in rows of {T}
    set end of values to value of static text 1 of UI element {column} of r
end repeat
set AppleScript's text item delimiters to linefeed
return values as text""")
            return text.splitlines()
        except RuntimeError:
            if attempt == 4:
                raise
            time.sleep(0.3)


def select(names):
    # Real modifier-clicks reach NSTableView's selection model; AXSelectedRows does not.
    for index, name in enumerate(names):
        row = shown().index(name) + 1
        x, y = ui.position(f"UI element 1 of row {row} of {T}")
        if index == 0:
            ui.left_click(x, y)
        else:
            ui.jxa(f"""ObjC.import("CoreGraphics"); ObjC.import("Foundation");
function command(down) {{
  var e = $.CGEventCreateKeyboardEvent($(), 55, down);
  $.CGEventSetFlags(e, down ? 0x100000 : 0); $.CGEventPost(0, e);
  $.NSThread.sleepForTimeInterval(0.1);
}}
command(true);
for (var type of [1, 2]) {{
  var e = $.CGEventCreateMouseEvent($(), type, $.CGPointMake({x}, {y}), 0);
  $.CGEventSetFlags(e, 0x100000); $.CGEventPost(0, e);
  $.NSThread.sleepForTimeInterval(0.1);
}}
// Release Command explicitly: it must not leak into subsequent menu typing.
command(false);""")


def toggle_queue():
    x, y = ui.position(f"button 2 of group 1 of {T}")
    ui.context_menu_pick(x, y, [12, 32, 14, 32, 14, 36])  # queue, Return
    time.sleep(1)


def reset_queue(ids):
    for position, ident in enumerate(ids):
        ui.rpc("torrent-set", ids=[ident], queuePosition=position)
    ui.wait_for(lambda: order() == ids, what="fixture queue order")
    time.sleep(1.5)


def move(kind, names, expected, ctrl=False):
    select(names)
    before = state()
    with lock:
        calls.clear()
    x, y = ui.position(f"UI element 1 of row {shown().index(names[0]) + 1} of {T}")
    ui.context_menu_pick(x, y, KEYS[kind], ctrl=ctrl)
    ui.wait_for(lambda: order() == expected, what=f"queue move {kind}")
    time.sleep(1.5)
    with lock:
        requests = list(calls)
    expected_ids = {t["id"] for t in before.values() if t["name"] in names}
    check(f"{kind}: one request for exactly the selected IDs",
          len(requests) == 1 and requests[0]["method"] == "queue-move-" + kind
          and set(requests[0]["arguments"]["ids"]) == expected_ids, requests)
    after = state()
    check(f"{kind}: status, location, labels and bandwidth priority unchanged",
          all(all(before[i][k] == after[i][k] for k in
                  ("status", "downloadDir", "labels", "bandwidthPriority")) for i in before))
    check(f"{kind}: one-based positions refreshed in the UI", displayed_positions() == [
        str(next(t["queuePosition"] for t in after.values() if t["name"] == name) + 1)
        for name in shown()])


def displayed_positions():
    # The enabled optional queue column follows the eleven default columns.
    return read_column(12)


proxy = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RecordingProxy)
threading.Thread(target=proxy.serve_forever, daemon=True).start()
ui.setup(APP)
ui.defaults("appLanguage", "english")
support = os.path.join(ui.HOME, "Library", "Application Support", "Transwift", "servers.json")
with open(support) as f:
    servers = json.load(f)
servers[0]["port"] = proxy.server_port
with open(support, "w") as f:
    json.dump(servers, f)
try:
    version = ui.rpc("session-get")["version"]
    check(f"actual daemon version: {version}",
          version.startswith("3.00") if ui.DAEMON == "tr3" else version.startswith("4."))
    ui.remove_all()
    ids = []
    names = []
    for index in range(12):
        name = f"queue-{11 - index:02d}"
        path = os.path.join(ui.WORK, name + ".torrent")
        ui.make_torrent(path, name=name, tracker="http://queue.uitest.invalid/announce")
        result = ui.rpc("torrent-add", metainfo=base64.b64encode(open(path, "rb").read()).decode(),
                        paused=True, **{"download-dir": "/downloads/queue" if index % 2 == 0 else "/downloads/other"})
        ids.append(result["torrent-added"]["id"])
        names.append(name)
    ui.rpc("torrent-set", ids=[ids[2], ids[5]], labels=["queue-test"])
    # Adding a paused torrent can briefly report "checking" during initial verification.
    ui.wait_for(lambda: all(t["status"] == 0 for t in state().values()),
                timeout=30, what="initial verification of paused fixtures")
    ui.launch(); ui.assert_isolated(); time.sleep(4); ui.activate()
    ui.ax("set size of window 1 to {1650, 800}")
    check("queue column hidden by default", int(ui.ax(f"count UI elements of row 1 of {T}")) == 11)
    toggle_queue()
    check("queue column can be enabled", int(ui.ax(f"count UI elements of row 1 of {T}")) == 12)
    # Queue sorting is numeric, including positions 10–12, and does not change daemon order.
    snapshot = order()
    ready(lambda: ui.click(f"button 12 of group 1 of {T}")); time.sleep(1)
    check("queue column sorts numerically", list(map(int, displayed_positions())) == list(range(1, 13)))
    check("table sorting does not reorder daemon queue", order() == snapshot)
    # Name order is deliberately the reverse of queue order.
    ready(lambda: ui.click(f"button 1 of group 1 of {T}")); time.sleep(1)
    for kind, picked, expected in [
        ("top", [2, 5], [2, 5, 0, 1, 3, 4, 6, 7, 8, 9, 10, 11]),
        ("up", [2, 5], [0, 2, 1, 3, 5, 4, 6, 7, 8, 9, 10, 11]),
        ("down", [2, 5], [0, 1, 3, 2, 4, 6, 5, 7, 8, 9, 10, 11]),
        ("bottom", [2, 5], [0, 1, 3, 4, 6, 7, 8, 9, 10, 11, 2, 5]),
    ]:
        reset_queue(ids)
        move(kind, [names[i] for i in reversed(picked)], [ids[i] for i in expected], ctrl=kind == "down")
    # A combined label + tracker + status filter contains non-adjacent queue positions.
    ready(lambda: ui.id_click("sidebar.filter.stopped"))
    ready(lambda: ui.id_click("sidebar.label.queue-test"))
    ready(lambda: ui.id_click("sidebar.tracker.queue.uitest.invalid"))
    time.sleep(1.5)
    check("combined filters narrow the visible selection", set(shown()) == {names[2], names[5]})
    reset_queue(ids)
    move("top", [names[5], names[2]], [ids[i] for i in [2, 5, 0, 1, 3, 4, 6, 7, 8, 9, 10, 11]])
    # Add the folder filter: only the even-indexed selected torrent is visible.
    ready(lambda: ui.id_click("sidebar.folder./downloads/queue"))
    time.sleep(1)
    check("folder combines with status, label and tracker", shown() == [names[2]])
    reset_queue(ids)
    move("bottom", [names[2]], [ids[i] for i in [0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 2]])
    # Keep the queue column when the app is reopened.
    ui.quit_app(); ui.launch(); ui.assert_isolated(); time.sleep(3)
    check("queue column visibility survives relaunch",
          int(ready(lambda: ui.ax(f"count UI elements of row 1 of {T}"))) == 12)
except Exception:
    print("Failure diagnostics: test pid", ui.pid(), flush=True)
    try:
        print("Test windows:", ui.windows(), flush=True)
        print("AX process state:", ui.ax("return {visible, frontmost, count windows}"), flush=True)
        print(ui.dump(), flush=True)
    except Exception as error:
        print("Could not read test window:", error, flush=True)
    raise
finally:
    ui.quit_app()
    ui.remove_all()
    ui.teardown()
    proxy.shutdown(); proxy.server_close()
print(f"\n{'all queue checks OK' if not failed else str(len(failed)) + ' failed'}", flush=True)
sys.exit(1 if failed else 0)
