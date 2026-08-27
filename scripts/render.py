#!/usr/bin/env python3
"""Render index.html (variant A) and feed.xml from tape/*.json. SPEC.md §5.

Stdlib only, no JS on the page. Called by the daily workflow after the tape is written.
"""
import argparse, datetime, email.utils, glob, html, json, os, sys

SITE = "https://neoyipeng2018.github.io/research-tape/"
ARCHIVE = "https://github.com/neoyipeng2018/research-tape/tree/main/tape"
FEED_DAYS = 30
CAP = 6  # ponytail: the cap in taste.md. A day under it is thin, and says so.

CSS = """\
:root { color-scheme: light dark;
        --bg:#faf9f7; --fg:#16150f; --dim:#7a776c; --rule:#e2ded4; }
@media (prefers-color-scheme: dark){ :root{ --bg:#12110f; --fg:#eae7dd; --dim:#8b8779; --rule:#2a2823; } }
* { box-sizing: border-box; }
body { margin: 0 auto; background:var(--bg); color:var(--fg);
       font: 15px/1.55 ui-monospace, SFMono-Regular, Menlo, monospace;
       max-width: 46rem; padding: 3rem 1.25rem 7rem; }
a { color: inherit; }
.head { display:flex; justify-content:space-between; align-items:baseline;
        border-bottom:2px solid var(--fg); padding-bottom:.4rem; margin-bottom:.2rem; }
.head b { font-weight:700; letter-spacing:.14em; text-transform:uppercase; font-size:.8rem; }
.head span { color:var(--dim); font-size:.78rem; }
.meta { color:var(--dim); font-size:.78rem; padding:.5rem 0 1.5rem; }
.row { display:grid; grid-template-columns:2rem 1fr; gap:.9rem;
       padding:1rem 0; border-bottom:1px solid var(--rule); }
.n { color:var(--dim); font-size:.78rem; padding-top:.15rem; }
.claim { margin:0 0 .35rem; }
.src { color:var(--dim); }
.ttl { display:block; font-size:.82rem; color:var(--dim); text-decoration:none; }
.ttl:hover { color:var(--fg); text-decoration:underline; }
.quiet { color:var(--dim); font-size:.82rem; padding:1.25rem 0 0; }
.foot { color:var(--dim); font-size:.78rem; padding-top:1.75rem; display:flex; gap:1rem; }
"""


def load(path):
    """A tape is {date, scanned, items:[{key, title, link, source, claim}]}. SPEC.md §5.

    Missing fields raise: a half-rendered page is worse than a dark day. SPEC.md §9.
    """
    with open(path) as f:
        return json.load(f)


def tapes(tape_dir):
    """Every tape file, newest day first."""
    return [load(p) for p in sorted(glob.glob(os.path.join(tape_dir, "*.json")), reverse=True)]


def long_date(iso):
    d = datetime.date.fromisoformat(iso)
    return f"{d:%A} {d.day} {d:%B %Y}"


def page(tape):
    items, e = tape["items"], html.escape
    # A prefix that reads on every row is noise, not provenance. SPEC.md §5.
    mixed = len({i["source"] for i in items}) > 1
    rows = "\n".join(f"""<div class="row">
  <div class="n">{n:02d}</div>
  <div>
    <p class="claim">{f'<span class="src">{e(it["source"])} —</span> ' if mixed else ''}{e(it["claim"])}</p>
    <a class="ttl" href="{e(it["link"], quote=True)}">{e(it["title"])}</a>
  </div>
</div>""" for n, it in enumerate(items, 1))
    quiet = ('<p class="quiet">Nothing else cleared the bar today.</p>'
             if len(items) < CAP else "")
    return f"""<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Research Tape — {e(tape["date"])}</title>
<link rel="alternate" type="application/rss+xml" title="Research Tape" href="feed.xml">
<style>
{CSS}</style>
<div class="head"><b>Research Tape</b><span>{e(long_date(tape["date"]))}</span></div>
<div class="meta">{len(items)} of {tape["scanned"]} scanned · arXiv + SSRN</div>
{rows}
{quiet}
<div class="foot"><a href="{ARCHIVE}">archive</a><a href="feed.xml">rss</a></div>
</html>
"""


def feed(all_tapes):
    e = html.escape
    def pub(iso):  # RFC 822, and never locale-dependent the way strftime is
        d = datetime.date.fromisoformat(iso)
        return email.utils.format_datetime(
            datetime.datetime(d.year, d.month, d.day, tzinfo=datetime.timezone.utc))
    items = "\n".join(f"""  <item>
    <title>{e(it["title"])}</title>
    <link>{e(it["link"])}</link>
    <description>{e(it["claim"])}</description>
    <pubDate>{pub(t["date"])}</pubDate>
    <guid isPermaLink="false">{e(it["key"])}</guid>
  </item>""" for t in all_tapes[:FEED_DAYS] for it in t["items"])
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
  <title>Research Tape</title>
  <link>{SITE}</link>
  <description>A daily AI-in-finance research tape: arXiv and SSRN, six items or fewer.</description>
  <language>en</language>
{items}
</channel>
</rss>
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tape-dir", default="tape")
    ap.add_argument("--out", default=".")
    a = ap.parse_args()

    all_tapes = tapes(a.tape_dir)
    if not all_tapes:
        sys.exit(f"no tape files in {a.tape_dir}/ — writing nothing")

    for name, text in (("index.html", page(all_tapes[0])),
                       ("feed.xml", feed(all_tapes))):
        with open(os.path.join(a.out, name), "w") as f:
            f.write(text)
    print(f"rendered {all_tapes[0]['date']}: {len(all_tapes[0]['items'])} items, "
          f"feed over {min(len(all_tapes), FEED_DAYS)} tapes")


if __name__ == "__main__":
    main()
