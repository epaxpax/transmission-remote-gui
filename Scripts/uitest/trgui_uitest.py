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
PROCESS = "TransmissionRemoteGUI"
RPC = "http://localhost:9099/transmission/rpc"
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
        json.dump([{"id": SERVER_ID, "name": "uitest-tr3", "host": "127.0.0.1", "port": 9099,
                    "useHTTPS": False, "username": "", "password": "", "refreshInterval": 1,
                    "path": "/transmission/rpc"}], f)
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
    if sh("docker", "start", "tr3", check=False).returncode != 0:
        sh("docker", "run", "-d", "--name", "tr3", "-p", "9099:9091",
           "linuxserver/transmission:version-3.00-r2")
    for _ in range(30):
        try:
            rpc("session-get")
            return
        except Exception:
            time.sleep(1)
    raise RuntimeError("tr3 daemon did not come up on :9099")


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


# ---------- Accessibility (System Events) ----------

def ax_enabled():
    return sh("osascript", "-e", 'tell application "System Events" to get UI elements enabled').stdout.strip() == "true"


def osa(script):
    return sh("osascript", "-e", script).stdout.strip()


def ax(body):
    """Runs AppleScript inside `tell process <app>` (requires Accessibility access)."""
    return osa(f'tell application "System Events" to tell (first process whose unix id is {pid()})\n{body}\nend tell')


def activate():
    osa(f'tell application "System Events" to set frontmost of (first process whose unix id is {pid()}) to true')


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
