#!/usr/bin/env python3
"""Builds the compact IP → country table the Peers tab uses for its flags.

Source: DB-IP "IP to Country Lite" (https://db-ip.com, CC BY 4.0) — the monthly CSV of
`first,last,country` rows. Usage:

    python3 Scripts/geoip.py OUT.bin                # downloads this (or last) month's CSV
    python3 Scripts/geoip.py OUT.bin --csv FILE.gz  # from a local CSV(.gz)

Output (raw-deflate compressed; `GeoIPTable` in TransmissionKit reads it):
    "TRGEO1"  u16 country count, 2-byte ASCII codes
    u32 n4,   n4 × u32 range starts (big endian),  n4 × u8 country index
    u32 n6,   n6 × u64 range starts (the top 64 bits of the IPv6 address), n6 × u8 index
Each range runs until the next start. Ranges with no country ("ZZ") map to index 0xFF,
and neighbouring ranges of the same country are merged. IPv6 is kept at /64 precision:
DB-IP allocations never split a /64, and the upper half is all a lookup needs.
"""
import datetime, gzip, io, ipaddress, struct, sys, urllib.request, zlib

URL = "https://download.db-ip.com/free/dbip-country-lite-{}.csv.gz"
NONE = 0xFF


def download():
    today = datetime.date.today().replace(day=1)
    for month in (today, (today - datetime.timedelta(days=1)).replace(day=1)):
        try:
            # DB-IP refuses Python's default User-Agent.
            req = urllib.request.Request(URL.format(month.strftime("%Y-%m")),
                                         headers={"User-Agent": "TransmissionRemoteGUI-build (+https://github.com/epaxpax/transmission-remote-gui)"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception as e:  # the new month's file appears a few days late
            print(f"geoip: {month:%Y-%m} not available ({e})", file=sys.stderr)
    sys.exit("geoip: no DB-IP country file could be downloaded")


def rows(data):
    text = gzip.decompress(data) if data[:2] == b"\x1f\x8b" else data
    for line in io.StringIO(text.decode("ascii")):
        first, last, cc = line.strip().split(",")
        yield ipaddress.ip_address(first), ipaddress.ip_address(last), cc


def build(data):
    codes, v4, v6 = [], [], []
    def index(cc):
        if cc == "ZZ" or len(cc) != 2:
            return NONE
        if cc not in codes:
            codes.append(cc)
        return codes.index(cc)
    for first, last, cc in rows(data):
        if first.version == 4:
            start, table = int(first), v4
        else:
            start, table = int(first) >> 64, v6
        idx = index(cc)
        if table and table[-1][0] == start:   # sub-/64 IPv6 split: keep the first
            continue
        if not table or table[-1][1] != idx:
            table.append((start, idx))
    if len(codes) >= NONE:
        sys.exit("geoip: too many country codes")
    out = bytearray(b"TRGEO1")
    out += struct.pack(">H", len(codes)) + "".join(codes).encode("ascii")
    for table, fmt in ((v4, ">I"), (v6, ">Q")):
        out += struct.pack(">I", len(table))
        out += b"".join(struct.pack(fmt, s) for s, _ in table)
        out += bytes(i for _, i in table)
    c = zlib.compressobj(9, zlib.DEFLATED, -15)   # raw deflate = Apple's COMPRESSION_ZLIB
    return c.compress(bytes(out)) + c.flush(), len(v4), len(v6), len(codes)


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        sys.exit(__doc__)
    out = args[0]
    data = open(args[2], "rb").read() if args[1:2] == ["--csv"] else download()
    blob, n4, n6, nc = build(data)
    with open(out, "wb") as f:
        f.write(blob)
    print(f"geoip: {n4} IPv4 + {n6} IPv6 ranges, {nc} countries → {out} ({len(blob) // 1024} KB)")


if __name__ == "__main__":
    main()
