#!/usr/bin/env python3
"""Update check + opt-in usage statistics, end to end against a LOCAL server (never GitHub or
GoatCounter). Both must stay unobtrusive: an automatic check pops nothing up (a newer release
is only a sidebar link, the alert opens on click), usage stats are never asked for and send
nothing until switched on; switched on, the daily ping carries only app / macOS / daemon
versions, and "Skip This Version" sticks."""
import http.server, json, os, sys, threading, time, urllib.parse
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
PORT = 9197
FAKE = "99.0.0"
pings, feeds = [], []
failed = []

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/latest.json":
            feeds.append(self.headers.get("User-Agent", ""))
            body = json.dumps({"tag_name": "v" + FAKE, "draft": False,
                               "html_url": "https://github.com/epaxpax/transmission-remote-gui/releases"}).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json")
            self.end_headers(); self.wfile.write(body)
        elif url.path == "/count":
            pings.append((urllib.parse.parse_qs(url.query), dict(self.headers)))
            self.send_response(200); self.end_headers()
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a):
        pass

def check(name, ok, detail=""):
    print(f"  {'✓' if ok else '✗'} {name}{'' if ok else '  → ' + str(detail)}")
    if not ok:
        failed.append(name)

def alert_button(title):
    """The window index holding a button with this title (an NSAlert), or None."""
    try:
        n = int(ui.ax("count windows"))
    except RuntimeError:
        return None
    for i in range(1, n + 1):
        try:
            if ui.ax(f'exists button "{title}" of window {i}') == "true":
                return f'button "{title}" of window {i}'
        except RuntimeError:
            pass
    return None

def press(title, timeout=40):
    elem = ui.wait_for(lambda: alert_button(title), timeout=timeout, what=f"'{title}' button")
    ui.click(elem); time.sleep(1)

SIDEGROUP = "group 1 of splitter group 1 of group 1 of window 1"

def update_button():
    """The sidebar's "New version" link-style button (status bar area), or None. With
    `.buttonStyle(.link)` AX reports it as a link, so it is not among the `button`s."""
    try:
        n = int(ui.ax(f"count UI elements of {SIDEGROUP}"))
    except RuntimeError:
        return None
    for i in range(1, n + 1):
        elem = f"UI element {i} of {SIDEGROUP}"
        try:
            if ui.ax(f'get value of attribute "AXIdentifier" of {elem}') == "sidebar.update":
                return elem
        except RuntimeError:
            pass
    return None

def read_default(key):
    r = ui.sh("defaults", "read", ui.BUNDLE_ID, key, check=False)
    return r.stdout.strip() if r.returncode == 0 else None

server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
ui.setup(APP)
ui.defaults("appLanguage", "english")
ui.defaults("updateCheckEnabled", True)
ui.sh("defaults", "delete", ui.BUNDLE_ID, "usageStatsEnabled", check=False)   # a fresh install
ui.defaults("updateFeedURL", f"http://127.0.0.1:{PORT}/latest.json")
ui.defaults("usagePingURL", f"http://127.0.0.1:{PORT}/count")
try:
    # 1) Fresh install: stats off and never asked; the update is only a sidebar link.
    ui.launch(); ui.assert_isolated(); ui.activate()
    ui.wait_for(lambda: feeds, timeout=30, what="the automatic update check")
    check("update feed asked with the app's User-Agent", feeds[0].startswith("TransmissionRemoteGUI/"), feeds)
    check("sidebar shows the new version", ui.wait_for(update_button, timeout=10, what="sidebar update button") is not None)
    time.sleep(8)
    check("automatic check pops nothing up", alert_button("Skip This Version") is None and alert_button("Later") is None)
    check("no stats question", alert_button("Yes, Send") is None and alert_button("No") is None)
    check("stats off by default: no ping", not pings, pings)

    ui.click(update_button()); time.sleep(1)
    press("Later")
    check("'Later' keeps the sidebar link", update_button() is not None)

    # 2) The user switched stats on (Settings → General): one ping a day, versions only.
    ui.quit_app(); ui.defaults("usageStatsEnabled", True); ui.launch(); ui.assert_isolated(); ui.activate()
    ui.wait_for(lambda: pings, timeout=30, what="usage ping")
    q, headers = pings[0]
    path = q.get("p", [""])[0]
    daemon = "tr-3.00" if ui.DAEMON == "tr3" else "tr-4."
    check("ping path = app / macOS / daemon version only",
          path.startswith("/app/") and "/macos-" in path and daemon in path, path)
    check("ping carries no other parameter", set(q) == {"p", "rnd"}, set(q))
    check("ping sends no cookie", "Cookie" not in headers, headers.get("Cookie"))
    check("ping sends no system language", headers.get("Accept-Language") in (None, "*"), headers.get("Accept-Language"))

    ui.wait_for(update_button, timeout=30, what="sidebar update button after relaunch")
    ui.click(update_button()); time.sleep(1)
    press("Skip This Version")
    check("skipped version stored", read_default("updateSkippedVersion") == FAKE, read_default("updateSkippedVersion"))
    check("sidebar link gone after skipping", update_button() is None)

    # 3) Same day again: no second ping, and the skipped version stays hidden.
    ui.quit_app(); pings.clear(); ui.launch(); ui.assert_isolated(); ui.activate(); time.sleep(12)
    check("no second ping on the same day", not pings, pings)
    check("skipped version not shown again", update_button() is None)
finally:
    ui.teardown(); server.shutdown()
print(f"\n{'all update/stats checks OK' if not failed else str(len(failed)) + ' failed'}")
sys.exit(1 if failed else 0)
