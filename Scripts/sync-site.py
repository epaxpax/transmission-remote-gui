#!/usr/bin/env python3
"""Keeps the website (docs/index.html) in sync with README.md.

The feature list and the screenshot gallery of the README are rendered into marked
regions of the page:

    <!-- sync:features:start --> … <!-- sync:features:end -->
    <!-- sync:gallery:start -->  … <!-- sync:gallery:end -->

Usage:
    Scripts/sync-site.py           # rewrite docs/index.html
    Scripts/sync-site.py --check   # exit 1 if the page is out of date (CI)
"""
import html, re, struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
PAGE = ROOT / "docs" / "index.html"


def section(md: str, title: str) -> str:
    m = re.search(rf"^## {re.escape(title)}\n(.*?)(?=^## |\Z)", md, re.S | re.M)
    if not m:
        sys.exit(f"README.md has no '## {title}' section")
    return m.group(1)


def inline(text: str) -> str:
    """The small Markdown subset the README uses: **bold**, `code`, [text](link)."""
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            out.append(f"<code>{html.escape(part[1:-1])}</code>")
            continue
        s = html.escape(part, quote=False)
        s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>', s)
        out.append(s)
    return "".join(out)


def features_html(md: str) -> str:
    lines = [l for l in section(md, "Features").splitlines() if l.strip()]
    out, open_sub = ['<ul class="featlist">'], False
    for line in lines:
        m = re.match(r"^( *)- (.*)$", line)
        if not m:
            continue
        nested, text = len(m.group(1)) >= 2, inline(m.group(2))
        if nested and not open_sub:
            out[-1] = out[-1].removesuffix("</li>") + "<ul>"
            open_sub = True
        elif not nested and open_sub:
            out.append("</ul></li>")
            open_sub = False
        out.append(f"<li>{text}</li>")
    if open_sub:
        out.append("</ul></li>")
    out.append("</ul>")
    return "\n  ".join(out)


def png_size(path: Path):
    with path.open("rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24]) if head[:8] == b"\x89PNG\r\n\x1a\n" else (None, None)


def gallery_html(md: str) -> str:
    out = []
    for src, alt in re.findall(r'<img src="docs/([^"]+)"[^>]*alt="([^"]*)"', section(md, "Torrent rules")):
        w, h = png_size(ROOT / "docs" / src)
        size = f' width="{w}" height="{h}"' if w else ""
        out.append(f'<img class="shot" src="{src}"{size} loading="lazy" decoding="async" alt="{html.escape(alt)}">')
    if not out:
        sys.exit("README.md '## Torrent rules' has no docs/ images")
    return "\n  ".join(out)


def render(page: str, md: str) -> str:
    for name, body in (("features", features_html(md)), ("gallery", gallery_html(md))):
        pat = re.compile(rf"(<!-- sync:{name}:start[^>]*-->\n).*?( *<!-- sync:{name}:end -->)", re.S)
        if not pat.search(page):
            sys.exit(f"docs/index.html has no sync:{name} markers")
        page = pat.sub(lambda m: m.group(1) + "  " + body + "\n" + m.group(2), page)
    return page


if __name__ == "__main__":
    md, page = README.read_text(), PAGE.read_text()
    new = render(page, md)
    if "--check" in sys.argv:
        if new != page:
            print("docs/index.html is out of sync with README.md — run Scripts/sync-site.py and commit.")
            sys.exit(1)
        print("website in sync with README")
    elif new != page:
        PAGE.write_text(new)
        print("docs/index.html updated from README.md")
    else:
        print("already in sync")
