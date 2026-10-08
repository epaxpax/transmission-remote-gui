#!/usr/bin/env python3
"""Peers tab: country flags from the bundled DB-IP table, numeric address sorting, sorting by
any column header (kept when switching tabs), and the DB-IP attribution. The daemon has no
swarm, so `peer_proxy` sits in front of it and hands the app a fixed set of peers."""
import base64, json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import trgui_uitest as ui, peer_proxy

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ui.ROOT, "dist", "Transmission Remote GUI.app")
T = "table 1 of scroll area 1 of group 1 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
TG = "tab group 1 of group 2 of splitter group 1 of group 2 of splitter group 1 of group 1 of window 1"
PEERS = f"outline 1 of scroll area 1 of group 1 of group 1 of {TG}"
PROXY_PORT = 9097
NUMERIC = ["1.1.1.1", "8.8.8.8", "80.80.80.80", "172.16.0.5", "193.6.1.1", "194.0.0.53", "2001:738::1"]
COUNTRY = {"1.1.1.1": "Australia", "8.8.8.8": "United States", "172.16.0.5": "", "80.80.80.80": "San Marino",
           "193.6.1.1": "Hungary", "194.0.0.53": "Germany", "2001:738::1": "Hungary"}
failed = []

def check(name, ok, detail=""):
    print(f"  {'✓' if ok else '✗'} {name}{'' if ok else '  → ' + str(detail)}")
    if not ok:
        failed.append(name)

def tab(name):
    ui.click(f'(first radio button of {TG} whose description is "{name}")'); time.sleep(2)

def cell(row, col):
    try:
        return ui.ax(f"get value of static text 1 of group 1 of UI element {col} of row {row} of {PEERS}")
    except RuntimeError:
        return ""   # an empty cell (no flag) has no text

def table():
    """[(address, country name)] in the order shown. Rows can be rebuilt mid-read by the
    1-second refresh — retry instead of failing on that race."""
    for attempt in range(5):
        try:
            n = int(ui.ax(f"count rows of {PEERS}"))
            return [(cell(i, 2), cell(i, 1)) for i in range(1, n + 1)]
        except RuntimeError:
            if attempt == 4:
                raise
            time.sleep(0.5)

def addresses():
    return [a for a, _ in table()]

def header(title):
    ui.click(f'(first button of group 1 of {PEERS} whose title is "{title}")'); time.sleep(1.5)

ui.setup(APP)
ui.defaults("appLanguage", "english")
proxy = peer_proxy.start(PROXY_PORT, ui.RPC)
servers = os.path.join(ui.HOME, "Library", "Application Support", "Transwift", "servers.json")
cfg = json.load(open(servers)); cfg[0]["port"] = PROXY_PORT; json.dump(cfg, open(servers, "w"))
try:
    ui.remove_all()
    path = os.path.join(ui.WORK, "peers-demo.torrent")
    ui.make_torrent(path, name="peers-demo")
    ui.rpc("torrent-add", metainfo=base64.b64encode(open(path, "rb").read()).decode(), paused=True)
    ui.launch(); ui.assert_isolated(); time.sleep(5); ui.activate()
    ui.ax(f'set value of attribute "AXSelected" of row 1 of {T} to true'); time.sleep(1)
    ui.click_toolbar("Details"); time.sleep(2)
    tab("Peers")
    ui.wait_for(lambda: len(table()) == len(NUMERIC), what="the proxy's peers in the Peers tab")
    time.sleep(1)   # the country table loads in the background

    rows = table()
    check("every peer gets its country (private address: none)",
          all(COUNTRY[a] == c for a, c in rows), [(a, c) for a, c in rows if COUNTRY[a] != c])
    check("addresses sort numerically by default, IPv4 before IPv6", addresses() == NUMERIC, addresses())
    header("Address")
    check("Address header again: descending", addresses() == NUMERIC[::-1], addresses())
    header("Country")
    names = [c for _, c in table()]
    known = [c for c in names if c]
    check("sorting by country: by name, unknown last", known == sorted(known) and names[-1] == "", names)
    header("Client")
    clients = [cell(i, 3) for i in range(1, len(NUMERIC) + 1)]
    check("sorting by client", clients == sorted(clients, key=str.lower), clients)
    tab("Trackers"); tab("Peers")
    clients_again = [cell(i, 3) for i in range(1, len(NUMERIC) + 1)]
    check("the chosen sort is kept when switching tabs", clients_again == clients, clients_again)
    header("Address")
    check("back to numeric address order", addresses() == NUMERIC, addresses())

    try:   # SwiftUI's Link shows up as an untitled AXLink element under the table
        link = ui.ax(f'exists (first UI element of group 1 of group 1 of {TG} whose role is "AXLink")') == "true"
    except RuntimeError:
        link = False
    check("DB-IP attribution shown", link)
    if os.environ.get("UITEST_SHOT"):
        ui.screenshot(os.environ["UITEST_SHOT"])
finally:
    ui.remove_all(); ui.teardown(); proxy.shutdown()
print(f"\n{'all peer checks OK' if not failed else str(len(failed)) + ' failed'}")
sys.exit(1 if failed else 0)
