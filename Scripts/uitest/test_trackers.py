#!/usr/bin/env python3
"""Tracker add/remove against the isolated tr3/tr4 daemons.

The recording loopback proxy verifies the app's actual writes. Fixtures use .invalid hosts
and paused torrents. No saved servers or NAS torrents are used.
"""
import base64
import hashlib
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
TG = "tab group 1 of group 2 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
A = "https://a.trackers.invalid/announce"
B = "udp://b.trackers.invalid:6969/announce"
C = "https://c.trackers.invalid/announce"
NEW = "https://new.trackers.invalid/announce"
EXTERNAL = "https://external.trackers.invalid/announce"
FIELDS = ("id", "trackers", "status", "downloadDir", "labels", "bandwidthPriority")
lock = threading.Lock()
calls = []
failed = []
reject_next = False


class RecordingProxy(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        global reject_next
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        request = json.loads(body)
        args = request.get("arguments", {})
        writing = request["method"] == "torrent-set" and any(
            key in args for key in ("trackerAdd", "trackerRemove", "trackerList"))
        if writing and reject_next:
            reject_next = False
            data = json.dumps({"result": "test rejection", "arguments": {}}).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        connection = http.client.HTTPConnection("127.0.0.1", ui.PORT, timeout=10)
        try:
            connection.request("POST", "/transmission/rpc", body, {
                "Content-Type": "application/json",
                "X-Transmission-Session-Id": self.headers.get("X-Transmission-Session-Id", ""),
            })
            response = connection.getresponse()
            data = response.read()
            if response.status == 200:
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


def rows():
    return {t["id"]: t for t in ui.torrents(FIELDS)}


def tiers(torrent):
    groups = {}
    for tracker in torrent["trackers"]:
        groups.setdefault(tracker["tier"], []).append(tracker["announce"])
    return [urls for _, urls in sorted(groups.items())]


def writes():
    with lock:
        return [r for r in calls if r["method"] == "torrent-set"]


def clear_calls():
    with lock:
        calls.clear()


def press(identifier, scope="window 1"):
    ui.activate()
    geometry = ui.ax_id(identifier, "return {position, size} of e", scope)
    x, y, width, height = (int(float(v)) for v in geometry.split(", "))
    ui.left_click(x + width // 2, y + height // 2)


def add_dialog(url):
    press("trackers.add")
    ui.wait_for(lambda: ui.id_exists("trackers.url", "sheet 1 of window 1"), what="add tracker sheet")
    press("trackers.url", "sheet 1 of window 1")
    # Paste ASCII fixtures so a host's Chinese IME cannot replace ':' with '：'.
    # Preserve all clipboard formats, including non-text data.
    ui.jxa("""ObjC.import("AppKit"); ObjC.import("Foundation"); ObjC.import("CoreGraphics");
var pb = $.NSPasteboard.generalPasteboard;
var saved = [];
var items = pb.pasteboardItems;
for (var i = 0; i < items.count; i++) {
    var item = items.objectAtIndex(i), copy = $.NSPasteboardItem.alloc.init;
    var types = item.types;
    for (var j = 0; j < types.count; j++) {
        var type = types.objectAtIndex(j);
        copy.setDataForType(item.dataForType(type), type);
    }
    saved.push(copy);
}
pb.clearContents;
pb.setStringForType($(""" + json.dumps(url) + """), $.NSPasteboardTypeString);
var writtenCount = pb.changeCount;
try {
    var se = Application("System Events");
    se.keystroke("a", {using: ["command down"]});
    se.keystroke("v", {using: ["command down"]});
    $.NSThread.sleepForTimeInterval(0.3);
} finally {
    // Release Command explicitly, as in test_queue.py's multi-selection helper.
    for (var key of [55, 54]) {
        var event = $.CGEventCreateKeyboardEvent($(), key, false);
        $.CGEventSetFlags(event, 0);
        $.CGEventPost(0, event);
    }
    if (pb.changeCount === writtenCount) {
        pb.clearContents;
        pb.writeObjects($(saved));
    }
}
""")
    ui.wait_for(lambda: ui.id_value("trackers.url", "sheet 1 of window 1") == url, what="tracker URL input")


def submit():
    ui.wait_for(lambda: ui.id_enabled("trackers.submit", "sheet 1 of window 1"), what="enabled Add")
    press("trackers.submit", "sheet 1 of window 1")
    ui.wait_for(lambda: not ui.id_exists("trackers.url", "sheet 1 of window 1"), what="tracker add completion")


def tracker_select(host):
    ui.ax_id("trackers.table", f'''repeat with r in rows of e
    if value of static text 1 of group 1 of UI element 1 of r contains "{host}" then
        set selected of r to true
        return
    end if
end repeat
error "tracker row not found"''')
    ui.wait_for(lambda: ui.id_enabled("trackers.remove"), what="tracker selection")


def remove(host, cancel=False):
    tracker_select(host)
    press("trackers.remove")
    ui.wait_for(lambda: ui.ax('exists sheet 1 of window 1') == "true", what="remove confirmation")
    if cancel:
        ui.ax("key code 53")
    else:
        press("trackers.confirmRemove", "sheet 1 of window 1")
    time.sleep(1)


def fixture(name, groups):
    data = b"fixture"
    info = {"name": name, "length": len(data), "piece length": 16384,
            "pieces": hashlib.sha1(data).digest()}
    metainfo = ui._bencode({"announce": groups[0][0], "announce-list": groups, "info": info})
    result = ui.rpc("torrent-add", metainfo=base64.b64encode(metainfo).decode(), paused=True)
    return result["torrent-added"]["id"]


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
    session = ui.rpc("session-get")
    version = session["rpc-version"]
    check(f"actual daemon version {session['version']} / RPC {version}",
          version == 16 if ui.DAEMON == "tr3" else version >= 17)
    ui.remove_all()
    target = fixture("tracker-target", [[A, B], [C]])
    other = fixture("tracker-other", [["https://other.trackers.invalid/announce"]])
    ui.wait_for(lambda: all(t["status"] == 0 for t in rows().values()), timeout=30, what="paused fixtures")
    initial = rows()
    ui.launch(); ui.assert_isolated(); ui.activate()
    ui.ax("set size of window 1 to {1650, 800}")
    ui.wait_for(lambda: ui.ax(f"count rows of {T}") == "2", what="torrent rows")
    ui.ax(f'''repeat with r in rows of {T}
    if value of static text 1 of UI element 1 of r is "tracker-target" then
        set selected of r to true
    end if
end repeat''')
    ui.ax('keystroke "i" using command down')
    ui.wait_for(lambda: ui.ax(f'exists (first radio button of {TG} whose description is "Trackers")') == "true", what="detail tabs")
    ui.click(f'(first radio button of {TG} whose description is "Trackers")')
    ui.wait_for(lambda: ui.id_exists("trackers.add"), what="tracker controls")
    check("remove disabled without a selected tracker", not ui.id_enabled("trackers.remove"))
    clear_calls()
    add_dialog("file:///tmp/not-a-tracker")
    check("invalid scheme disables Add", not ui.id_enabled("trackers.submit", "sheet 1 of window 1"))
    ui.ax("key code 53")
    check("cancelled add sends no write", not writes() and rows() == initial)
    # Another client's update while the editor is open must survive our new addition.
    add_dialog(NEW)
    ui.rpc("torrent-set", ids=[target], trackerAdd=[EXTERNAL])
    clear_calls()
    submit()
    ui.wait_for(lambda: any(t["announce"] == NEW for t in rows()[target]["trackers"]), what="new tracker")
    check("existing tiers and concurrent external tracker preserved",
          tiers(rows()[target]) == tiers(initial[target]) + [[EXTERNAL], [NEW]], tiers(rows()[target]))
    accepted = writes()
    key = "trackerList" if version >= 17 else "trackerAdd"
    check("version-specific write targets only the selected torrent",
          len(accepted) == 1 and set(accepted[0]["arguments"]) == {"ids", key}
          and accepted[0]["arguments"]["ids"] == [target], accepted)
    with lock:
        before_write = calls[:calls.index(accepted[0])]
    check("fresh tracker-only read precedes the write", any(
        r["method"] == "torrent-get" and r["arguments"].get("fields") == ["id", "trackers"]
        and r["arguments"].get("ids") == [target] for r in before_write))
    ui.wait_for(lambda: ui.id_exists("sidebar.tracker.new.trackers.invalid"), what="sidebar cache update")
    check("new tracker host appears immediately in sidebar", True)
    clear_calls()
    add_dialog(NEW); submit()
    check("duplicate add is idempotent", not writes())
    clear_calls()
    remove("new.trackers.invalid", cancel=True)
    check("cancelled removal sends no write", not writes() and any(
        t["announce"] == NEW for t in rows()[target]["trackers"]))
    remove("new.trackers.invalid")
    ui.wait_for(lambda: all(t["announce"] != NEW for t in rows()[target]["trackers"]), what="tracker removal")
    check("removal preserves all other tiers", tiers(rows()[target]) == tiers(initial[target]) + [[EXTERNAL]])
    accepted = writes()
    key = "trackerList" if version >= 17 else "trackerRemove"
    check("version-specific removal targets only the selected torrent", len(accepted) == 1
          and set(accepted[0]["arguments"]) == {"ids", key} and accepted[0]["arguments"]["ids"] == [target])
    ui.wait_for(lambda: not ui.id_exists("sidebar.tracker.new.trackers.invalid"), what="removed sidebar host")
    check("removed host disappears without the five-minute cache delay", True)
    # The app should keep the sheet open with an error and permit a retry.
    reject_next = True
    add_dialog(NEW)
    press("trackers.submit", "sheet 1 of window 1")
    ui.wait_for(lambda: ui.id_exists("trackers.error", "sheet 1 of window 1"), what="write error")
    check("daemon error remains visible in the add sheet", ui.id_enabled("trackers.submit", "sheet 1 of window 1"))
    submit()
    ui.wait_for(lambda: any(t["announce"] == NEW for t in rows()[target]["trackers"]), what="successful retry")
    check("failed write can be retried", True)
    for host in ["a.trackers.invalid", "b.trackers.invalid", "c.trackers.invalid", "external.trackers.invalid", "new.trackers.invalid"]:
        remove(host)
    ui.wait_for(lambda: not rows()[target]["trackers"], what="empty tracker list")
    check("last tracker can be removed and empty state retains Add", ui.id_enabled("trackers.add"))
    check("empty state disables Remove", not ui.id_enabled("trackers.remove"))
    add_dialog("udp://udp.trackers.invalid:6969/announce"); submit()
    check("UDP tracker can be added to an empty list", tiers(rows()[target]) == [["udp://udp.trackers.invalid:6969/announce"]])
    after = rows()
    check("other torrent is untouched", after[other] == initial[other])
    check("target status, location, labels and bandwidth priority preserved", all(
        after[target][k] == initial[target][k] for k in ("status", "downloadDir", "labels", "bandwidthPriority")))
finally:
    if sys.exc_info()[0]:
        try:
            print("Failure input value:", ui.id_value("trackers.url", "sheet 1 of window 1"), flush=True)
        except Exception as error:
            print("Could not read failure window:", error, flush=True)
    ui.teardown()
    ui.remove_all()
    proxy.shutdown()
print(f"\n{len(failed)} failed", flush=True)
sys.exit(bool(failed))
