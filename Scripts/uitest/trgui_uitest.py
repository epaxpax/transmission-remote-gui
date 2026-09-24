#!/usr/bin/env python3
"""UI test harness for Transmission Remote GUI (no Xcode needed).

Runs an ISOLATED copy of the built app against the throw-away `tr3` docker daemon
(localhost:9099), so the real app, its saved servers and the real seedbox are never touched:
  * separate bundle id  → separate UserDefaults / LaunchServices identity
  * CFFIXED_USER_HOME   → separate Application Support (servers.json, rules, RSS)

Primitives: launch/quit, RPC against the test daemon, window listing (CoreGraphics),
per-window screenshots, and — when the terminal has Accessibility access — AX clicks/keys
via System Events.
"""
import json, os, plistlib, shutil, subprocess, sys, time, urllib.request, hashlib, random, base64

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.environ.get("UITEST_WORK", os.path.join(ROOT, ".build", "uitest"))
APP = os.path.join(WORK, "TRGUI UITest.app")
HOME = os.path.join(WORK, "home")
BUNDLE_ID = "io.github.epaxpax.TransmissionRemoteGUI.uitest"
# The copy's executable is renamed: the real app's process is also "TransmissionRemoteGUI",
# and System Events may resolve a pid-based reference by NAME — i.e. to the real app.
PROCESS = "TRGUIUITest"
# Test daemon: UITEST_DAEMON=tr3 (Transmission 3.00, default) or tr4 (latest 4.x).
DAEMONS = {"tr3": (9099, "linuxserver/transmission:version-3.00-r2"),
           "tr4": (9098, "linuxserver/transmission:latest")}
DAEMON = os.environ.get("UITEST_DAEMON", "tr3")
PORT, IMAGE = DAEMONS[DAEMON]
RPC = f"http://localhost:{PORT}/transmission/rpc"
SERVER_ID = "0A7E57E5-0000-4000-8000-00000000C0DE"


def sh(*args, check=True, **kw):
    return subprocess.run(args, check=check, text=True, capture_output=True, **kw)


# ---------- setup ----------

def setup(source_app=os.path.join(ROOT, "dist", "Transmission Remote GUI.app")):
    """Copies the built app, re-identifies it, and writes an isolated home pointing at tr3."""
    quit_app()
    shutil.rmtree(APP, ignore_errors=True)
    shutil.copytree(source_app, APP, symlinks=True)
    plist_path = os.path.join(APP, "Contents", "Info.plist")
    with open(plist_path, "rb") as f:
        info = plistlib.load(f)
    info["CFBundleIdentifier"] = BUNDLE_ID
    macos = os.path.join(APP, "Contents", "MacOS")
    os.rename(os.path.join(macos, info["CFBundleExecutable"]), os.path.join(macos, PROCESS))
    info["CFBundleExecutable"] = PROCESS
    info["CFBundleName"] = info["CFBundleDisplayName"] = "TRGUI UITest"
    # Never let the copy become a system handler for magnet links / .torrent files: launched
    # by LaunchServices it would lack CFFIXED_USER_HOME and see the REAL servers.
    info.pop("CFBundleURLTypes", None)
    info.pop("CFBundleDocumentTypes", None)
    with open(plist_path, "wb") as f:
        plistlib.dump(info, f)
    sh("codesign", "--force", "--deep", "-s", "-", APP)

    shutil.rmtree(HOME, ignore_errors=True)
    support = os.path.join(HOME, "Library", "Application Support", "Transwift")
    os.makedirs(support)
    with open(os.path.join(support, "servers.json"), "w") as f:
        json.dump([{"id": SERVER_ID, "name": "uitest-tr3", "host": "127.0.0.1", "port": PORT,
                    "useHTTPS": False, "username": "", "password": "", "refreshInterval": 1,
                    "path": "/transmission/rpc"}], f)
    # Rules, RSS and settings live in the copy's UserDefaults: start every run from scratch.
    sh("defaults", "delete", BUNDLE_ID, check=False)
    defaults("selectedServerID", SERVER_ID)
    ensure_daemon()


def defaults(key, value):
    kind = "-bool" if isinstance(value, bool) else "-string"
    sh("defaults", "write", BUNDLE_ID, key, kind, str(value).lower() if isinstance(value, bool) else str(value))


def teardown():
    quit_app()
    lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    sh(lsregister, "-u", APP, check=False)
    sh("defaults", "delete", BUNDLE_ID, check=False)
    shutil.rmtree(APP, ignore_errors=True)


def ensure_daemon():
    if sh("docker", "start", DAEMON, check=False).returncode != 0:
        sh("docker", "run", "-d", "--name", DAEMON, "-p", f"{PORT}:9091", IMAGE)
    for _ in range(30):
        try:
            rpc("session-get")
            return
        except Exception:
            time.sleep(1)
    raise RuntimeError(f"{DAEMON} daemon did not come up on :{PORT}")


# ---------- app lifecycle ----------

def launch(*open_args):
    """Launches (or, if running, sends open events to) the isolated app."""
    sh("open", "--env", f"CFFIXED_USER_HOME={HOME}", "-a", APP, *open_args)


def assert_isolated():
    """Fails loudly if the running copy is not connected to the test daemon (isolation broken)."""
    wins = wait_for(windows, what="a window")
    names = {w["name"] for w in wins}
    assert "uitest-tr3" in names, f"app is not on the test server (windows: {names}) — isolation broken"


def pid():
    r = sh("pgrep", "-f", os.path.join(APP, "Contents", "MacOS", PROCESS), check=False)
    pids = r.stdout.split()
    return int(pids[0]) if pids else None


def wait_for(cond, timeout=15, step=0.3, what="condition"):
    end = time.time() + timeout
    while time.time() < end:
        v = cond()
        if v:
            return v
        time.sleep(step)
    raise AssertionError(f"timed out waiting for {what}")


def quit_app():
    p = pid()
    if p:
        subprocess.run(["kill", str(p)])
        try:
            wait_for(lambda: pid() is None, timeout=5, what="app exit")
        except AssertionError:
            subprocess.run(["kill", "-9", str(p)])


# ---------- windows / screenshots (CoreGraphics, no Accessibility needed) ----------

_WIN_SWIFT = r'''
import CoreGraphics; import Foundation
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
var out: [[String: Any]] = []
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
    out.append(["id": w[kCGWindowNumber as String]!, "name": w[kCGWindowName as String] ?? "", "bounds": w[kCGWindowBounds as String]!])
}
print(String(data: try! JSONSerialization.data(withJSONObject: out), encoding: .utf8)!)
'''


def windows():
    """Normal (layer 0) on-screen windows of the app: [{id, name, bounds}]."""
    p = pid()
    if not p:
        return []
    script = os.path.join(WORK, "windows.swift")
    os.makedirs(WORK, exist_ok=True)
    if not os.path.exists(script) or open(script).read() != _WIN_SWIFT:
        with open(script, "w") as f:
            f.write(_WIN_SWIFT)
    return json.loads(sh("swift", script, str(p)).stdout)


def screenshot(path, window_id=None):
    wid = window_id or (windows() or [{}])[0].get("id")
    if not wid:
        raise AssertionError("no window to screenshot")
    sh("screencapture", "-x", "-o", f"-l{wid}", path)
    return path


# ---------- Accessibility (System Events, via the helper app) ----------
#
# AppleScript UI scripting runs through "TRGUI UITest Helper.app" (Scripts/uitest/helper):
# macOS grants Accessibility to the responsible app, and a process spawned from a terminal /
# Claude Code is attributed to `osascript`, which cannot be picked in System Settings.

HELPER = "/Applications/TRGUI UITest Helper.app"
_seq = 0


def osa(script):
    global _seq
    _seq += 1
    src = os.path.join(WORK, f"ax-{_seq}.applescript")
    out = os.path.join(WORK, f"ax-{_seq}.json")
    with open(src, "w") as f:
        f.write(script)
    if os.path.exists(out):
        os.remove(out)
    sh("open", "-g", "-W", "-n", "-a", HELPER, "--args", src, out)   # -g: never steal focus
    wait_for(lambda: os.path.exists(out), timeout=30, step=0.1, what="helper result")
    time.sleep(0.05)
    with open(out) as f:
        r = json.load(f)
    os.remove(src); os.remove(out)
    if not r["trusted"]:
        raise RuntimeError(f"{HELPER} has no Accessibility access (System Settings → Privacy → Accessibility)")
    if r["status"] != 0:
        raise RuntimeError(r["stderr"].strip())
    return r["stdout"].strip()


def ax_enabled():
    try:
        # (`UI elements enabled` reports the legacy global flag, not this app's grant.)
        return bool(osa('tell application "System Events" to get name of first process whose frontmost is true'))
    except Exception:
        return False


def ax(body):
    """Runs AppleScript inside `tell process <app>`."""
    assert pid(), "test app is not running"
    return osa(f'tell application "System Events" to tell process "{PROCESS}"\n{body}\nend tell')


def activate():
    ax("set frontmost to true")


# ---------- RPC against the test daemon ----------

_session = None


def rpc(method, **arguments):
    global _session
    body = json.dumps({"method": method, "arguments": arguments}).encode()
    for _ in range(2):
        req = urllib.request.Request(RPC, data=body, headers={"X-Transmission-Session-Id": _session or ""})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                resp = json.load(r)
                if resp.get("result") != "success":
                    raise RuntimeError(resp)
                return resp.get("arguments", {})
        except urllib.error.HTTPError as e:
            if e.code == 409:
                _session = e.headers["X-Transmission-Session-Id"]
                continue
            raise
    raise RuntimeError("RPC session handshake failed")


def torrents(fields=("id", "name", "hashString")):
    return rpc("torrent-get", fields=list(fields))["torrents"]


def remove_all():
    ids = [t["id"] for t in torrents()]
    if ids:
        rpc("torrent-remove", ids=ids, **{"delete-local-data": True})


# ---------- fixtures ----------

def _bencode(v):
    if isinstance(v, int):
        return b"i%de" % v
    if isinstance(v, bytes):
        return b"%d:%s" % (len(v), v)
    if isinstance(v, str):
        return _bencode(v.encode())
    if isinstance(v, list):
        return b"l" + b"".join(map(_bencode, v)) + b"e"
    if isinstance(v, dict):
        return b"d" + b"".join(_bencode(k) + _bencode(v[k]) for k in sorted(v)) + b"e"
    raise TypeError(v)


def make_torrent(path, name=None, tracker="http://tracker.uitest.invalid/announce"):
    """Writes a valid single-file .torrent (random content) and returns its info-hash."""
    name = name or f"uitest-{random.randrange(10**8)}.bin"
    data = os.urandom(32 * 1024)
    piece = 16 * 1024
    pieces = b"".join(hashlib.sha1(data[i:i + piece]).digest() for i in range(0, len(data), piece))
    info = {"name": name, "length": len(data), "piece length": piece, "pieces": pieces}
    with open(path, "wb") as f:
        f.write(_bencode({"announce": tracker, "info": info}))
    return hashlib.sha1(_bencode(info)).hexdigest()


def make_magnet(name="uitest-magnet"):
    h = hashlib.sha1(os.urandom(20)).hexdigest()
    return h, f"magnet:?xt=urn:btih:{h}&dn={name}"


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    {"setup": setup, "teardown": teardown, "quit": quit_app}.get(cmd, lambda: print(__doc__))()


# ---------- AX tree helpers ----------

def dump(target="window 1"):
    """Indented tree under `target`: class | description | title | value | enabled."""
    script = '''
on walk(e, ind)
    set c to ""
    set d to ""
    set t to ""
    set v to ""
    set en to ""
    tell application "System Events"
        try
            set c to (class of e) as text
        end try
        try
            set d to (description of e) as text
        end try
        try
            set t to (title of e) as text
        end try
        try
            set v to (value of e) as text
        end try
        try
            set en to (enabled of e) as text
        end try
        try
            set h to (help of e) as text
            if h is not "missing value" then set d to d & " ?" & h
        end try
        try
            set nm to (name of e) as text
            if nm is not "missing value" then set t to t & " @" & nm
        end try
        set kids to {}
        try
            set kids to UI elements of e
        end try
    end tell
    set out to ind & c & " | " & d & " | " & t & " | " & v & " | " & en & linefeed
    repeat with k in kids
        set out to out & my walk(contents of k, ind & "  ")
    end repeat
    return out
end walk
tell application "System Events"
    set root to TARGET of process "PROC"
end tell
return walk(root, "")
'''
    return osa(script.replace("TARGET", target).replace("PROC", PROCESS))


def click_toolbar(desc):
    ax(f'click (first button of toolbar 1 of window 1 whose description is "{desc}")')


def type_into(elem, text):
    """Focuses a text field (AX path inside the process) and replaces its text by typing."""
    ax(f'''set frontmost to true
set focused of {elem} to true
keystroke "a" using command down
keystroke "{text}"''')


def click(elem):
    ax(f'perform action "AXPress" of {elem}')


def position(elem):
    """Centre of an element in global screen points."""
    out = ax(f'get {{position, size}} of {elem}')
    x, y, w, h = (float(v) for v in out.split(", "))
    return x + w / 2, y + h / 2


def drag(x1, y1, x2, y2, steps=20):
    """Real mouse drag (CGEvent) — for SwiftUI List .onMove, which has no AX action."""
    js = f'''
ObjC.import("CoreGraphics"); ObjC.import("Foundation");
function ev(t, x, y) {{ var e = $.CGEventCreateMouseEvent($(), t, $.CGPointMake(x, y), 0); $.CGEventPost(0, e); }}
function nap(s) {{ $.NSThread.sleepForTimeInterval(s); }}
ev(5, {x1}, {y1}); nap(0.1);
ev(1, {x1}, {y1}); nap(0.4);
for (var i = 1; i <= {steps}; i++) {{ ev(6, {x1} + ({x2} - {x1}) * i / {steps}, {y1} + ({y2} - {y1}) * i / {steps}); nap(0.03); }}
nap(0.4); ev(2, {x2}, {y2}); nap(0.2);
'''
    osa(f'run script "{js.replace(chr(34), chr(92) + chr(34))}" in "JavaScript"')


def right_click(x, y, ctrl=False):
    """Real secondary click (or Ctrl+primary click) via CGEvent."""
    if ctrl:
        js = f'''ObjC.import("CoreGraphics"); ObjC.import("Foundation");
function ev(t) {{ var e = $.CGEventCreateMouseEvent($(), t, $.CGPointMake({x}, {y}), 0); $.CGEventSetFlags(e, 0x40000); $.CGEventPost(0, e); }}
ev(5); $.NSThread.sleepForTimeInterval(0.1); ev(1); $.NSThread.sleepForTimeInterval(0.05); ev(2);'''
    else:
        js = f'''ObjC.import("CoreGraphics"); ObjC.import("Foundation");
function ev(t) {{ var e = $.CGEventCreateMouseEvent($(), t, $.CGPointMake({x}, {y}), 1); $.CGEventPost(0, e); }}
ev(5); $.NSThread.sleepForTimeInterval(0.1); ev(3); $.NSThread.sleepForTimeInterval(0.05); ev(4);'''
    osa(f'run script "{js.replace(chr(34), chr(92) + chr(34))}" in "JavaScript"')


def jxa(code):
    """Runs JavaScript for Automation through the helper (no string escaping needed)."""
    global _seq
    _seq += 1
    path = os.path.join(WORK, f"jxa-{_seq}.js")
    with open(path, "w") as f:
        f.write(code)
    try:
        return osa(f'run script (POSIX file "{path}") in "JavaScript"')
    finally:
        os.remove(path)


def context_menu_items(x, y, ctrl=False, shot_path=None):
    """Opens the context menu at (x, y) with a real click, returns its item titles, closes it."""
    flags = "0x40000" if ctrl else "0"
    down, up, button = (1, 2, 0) if ctrl else (3, 4, 1)
    shot = (f'app.doShellScript("screencapture -x -R{int(x - 250)},{int(y - 40)},700,520 \'{shot_path}\'");'
            if shot_path else "")
    return jxa(f'''
ObjC.import("CoreGraphics"); ObjC.import("Foundation");
var app = Application.currentApplication(); app.includeStandardAdditions = true;
function ev(t) {{ var e = $.CGEventCreateMouseEvent($(), t, $.CGPointMake({x}, {y}), {button});
  $.CGEventSetFlags(e, {flags}); $.CGEventPost(0, e); }}
ev(5); $.NSThread.sleepForTimeInterval(0.1); ev({down}); $.NSThread.sleepForTimeInterval(0.05); ev({up});
$.NSThread.sleepForTimeInterval(0.8);
var names = [];
try {{
  var p = Application("System Events").processes.byName("{PROCESS}");
  var els = p.uiElements();   // a context menu is a top-level AXMenu of the app
  for (var i = 0; i < els.length; i++) {{
    if (els[i].role() === "AXMenu") {{ names = els[i].menuItems.name(); break; }}
  }}
}} catch (e) {{ names = ["ERR " + e]; }}
{shot}
var k = $.CGEventCreateKeyboardEvent($(), 53, true); $.CGEventPost(0, k);
var k2 = $.CGEventCreateKeyboardEvent($(), 53, false); $.CGEventPost(0, k2);
names.map(function (n) {{ return n === null ? "-" : n; }}).join("|");
''')


def context_menu_pick(x, y, keycodes, ctrl=False):
    """Opens the context menu at (x, y) with a real click, then drives it with key presses
    (type-select + Return). While a menu is tracking, AX cannot read it — keys still work."""
    flags = "0x40000" if ctrl else "0"
    down, up, button = (1, 2, 0) if ctrl else (3, 4, 1)
    keys = ", ".join(str(k) for k in keycodes)
    return jxa(f'''var CTRL = {"true" if ctrl else "false"};
ObjC.import("CoreGraphics"); ObjC.import("Foundation");
function nap(s) {{ $.NSThread.sleepForTimeInterval(s); }}
function ev(t) {{ var e = $.CGEventCreateMouseEvent($(), t, $.CGPointMake({x}, {y}), {button});
  $.CGEventSetFlags(e, {flags}); $.CGEventPost(0, e); }}
function key(k) {{ $.CGEventPost(0, $.CGEventCreateKeyboardEvent($(), k, true)); nap(0.03);
  $.CGEventPost(0, $.CGEventCreateKeyboardEvent($(), k, false)); nap(0.08); }}
function mod(isDown) {{ var e = $.CGEventCreateKeyboardEvent($(), 59, isDown); $.CGEventSetFlags(e, isDown ? 0x40000 : 0); $.CGEventPost(0, e); nap(0.05); }}
ev(5); nap(0.1);
if (CTRL) mod(true);
ev({down}); nap(0.05); ev({up});
if (CTRL) mod(false);
nap(0.8);
[{keys}].forEach(key);
"ok"''')


KEY_MOVE = [46, 31, 9, 14, 36]      # type-select "move", Return
