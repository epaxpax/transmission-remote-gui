"""A pass-through proxy in front of the test daemon that adds made-up peers to every
`torrent-get` response asking for `peers`. The docker daemons have no swarm, and the suites
must not join a real one — so the Peers tab gets its rows from here. The addresses belong to
well-known public services (DNS resolvers, a university network), not to anyone's machine."""
import http.server, json, threading, urllib.error, urllib.request

PEERS = [
    {"address": "193.6.1.1", "clientName": "Transmission 4.0.5", "progress": 1.0, "rateToClient": 131072, "rateToPeer": 0},
    {"address": "8.8.8.8", "clientName": "qBittorrent/5.1.0", "progress": 0.42, "rateToClient": 65536, "rateToPeer": 2048},
    {"address": "1.1.1.1", "clientName": "libtorrent/1.2.18", "progress": 1.0, "rateToClient": 0, "rateToPeer": 0},
    {"address": "194.0.0.53", "clientName": "µTorrent 3.6", "progress": 0.14, "rateToClient": 8192, "rateToPeer": 512},
    {"address": "80.80.80.80", "clientName": "Deluge 2.1.1", "progress": 0.75, "rateToClient": 32768, "rateToPeer": 0},
    {"address": "2001:738::1", "clientName": "BiglyBT 3.6", "progress": 1.0, "rateToClient": 16384, "rateToPeer": 0},
    {"address": "172.16.0.5", "clientName": "Transmission 3.00", "progress": 0.0, "rateToClient": 0, "rateToPeer": 0},
]
for p in PEERS:
    p.setdefault("flagStr", "D")
    p.setdefault("isEncrypted", False)


def start(port, upstream):
    """Serves on 127.0.0.1:`port`, forwarding to the `upstream` RPC URL; returns the server."""
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            headers = {k: v for k, v in self.headers.items() if k.lower() in ("x-transmission-session-id", "content-type", "authorization")}
            req = urllib.request.Request(upstream, data=body, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    status, data, extra = r.status, r.read(), {}
            except urllib.error.HTTPError as e:
                status, data = e.code, e.read()
                extra = {"X-Transmission-Session-Id": e.headers.get("X-Transmission-Session-Id", "")}
            try:
                asked = json.loads(body)
                if asked.get("method") == "torrent-get" and "peers" in asked.get("arguments", {}).get("fields", []):
                    resp = json.loads(data)
                    for t in resp.get("arguments", {}).get("torrents", []):
                        t["peers"] = PEERS
                    data = json.dumps(resp).encode()
            except ValueError:
                pass
            self.send_response(status)
            for k, v in extra.items():
                self.send_header(k, v)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
