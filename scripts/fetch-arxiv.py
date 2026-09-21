#!/usr/bin/env python3
"""The arXiv lane: one call, trailing 7 days, candidates out. SPEC.md §1.1.

The query lives in taste.md (## Queries, the `arxiv:` line), never here. One request per
run, so the 1 req/3s ToU limit needs no pacing. An unreachable or garbage arXiv degrades
to zero candidates and exit 0 — the day publishes from Crossref alone (§9).
"""
import argparse, datetime, json, os, re, subprocess, sys, urllib.error, urllib.parse, urllib.request
import xml.etree.ElementTree as ET

from lane import dead_days   # one streak counter for both lanes

API = "https://export.arxiv.org/api/query"  # http:// 301s
ATOM = "{http://www.w3.org/2005/Atom}"
UA = "research-tape/0.1 (https://github.com/neoyipeng2018/research-tape)"
HEADERS = {"User-Agent": UA, "Accept": "application/atom+xml,text/xml;q=0.9,*/*;q=0.8"}
WINDOW_DAYS = 7  # never one day: the search index runs ~3 days behind announcements
TIMEOUT = 60
KEY = re.compile(r"\A(?:[a-z-]+(?:\.[A-Z]{2})?/)?\d{4,7}\.?\d{3,5}\Z")  # new and legacy ids


def taste_query(path):
    """The `arxiv:` line of ## Queries, indented continuations folded in."""
    line = []
    section = False
    with open(path) as f:
        for raw in f:
            if raw.startswith("## "):
                section = raw.strip() == "## Queries"
            elif section and raw.startswith("arxiv: "):
                line = [raw[len("arxiv: "):]]
            elif line and raw[:1].isspace():   # any indent continues, as validate-taste.sh reads it
                line.append(raw)
            elif line:
                break
    if not line:
        sys.exit(f"{path}: ## Queries has no 'arxiv: ' line")
    return " ".join(s.strip() for s in line)


def search_query(expr, now):
    """The window, stamped to the *day* and not the minute. A minute stamp makes the URL
    unique on every run, so every run is a guaranteed Fastly cache miss at arXiv's edge —
    and a miss is what gets refused (docs/adr/0001). Rounded, the day's runs share one URL
    and so does every other q-fin harvester asking the same thing. The end of today rather
    than this minute, so the window never excludes a paper submitted an hour ago."""
    since = now - datetime.timedelta(days=WINDOW_DAYS)
    return (f"({expr}) AND submittedDate:"
            f"[{since:%Y%m%d}0000 TO {now:%Y%m%d}2359]")


def strip_v(s):
    return re.sub(r"v\d+$", "", s)


def flat(s):
    return re.sub(r"\s+", " ", s or "").strip()


def parse(xml):
    """Atom -> candidate records: key, source, title, abstract, link."""
    out = []
    for e in ET.fromstring(xml).iter(ATOM + "entry"):
        aid = e.findtext(ATOM + "id", "").split("/abs/")
        key = strip_v(aid[1]) if len(aid) == 2 else ""
        abstract = flat(e.findtext(ATOM + "summary"))
        # arXiv answers a bad query with HTTP 200 and a well-formed feed whose one entry is an
        # error, id `.../api/errors#...`. No /abs/, no key, dropped here. An abstract-less entry
        # goes too: its fingerprint is the empty set and §2 divides by the union.
        if not KEY.match(key) or not abstract:
            continue
        out.append({
            "key": key,
            "source": "arXiv",
            "title": flat(e.findtext(ATOM + "title")),
            "abstract": abstract,
            "link": f"https://arxiv.org/abs/{key}",
        })
    return out


def curl(url):
    """The same URL through curl, which is preinstalled on ubuntu-latest. arXiv's edge
    refused stdlib urllib from the runner for ten days while curl to the same URL was
    reported working elsewhere: urllib's header set and ordering are a fingerprint, and
    this is the cheap way to stop matching it without taking on a pip dependency."""
    p = subprocess.run(["curl", "-sSLf", "--max-time", str(TIMEOUT), "-A", UA,
                        "-H", "Accept: " + HEADERS["Accept"], url],
                       capture_output=True)
    if p.returncode:
        raise OSError(f"curl exit {p.returncode}: {p.stderr.decode(errors='replace').strip()}")
    return p.stdout


def fetch(expr, now):
    url = API + "?" + urllib.parse.urlencode({
        "search_query": search_query(expr, now),
        "max_results": 2000,   # arXiv's documented per-request cap, not over it
    })
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        if e.code != 406:
            raise
        print(f"arxiv: 406 from urllib, retrying the same URL through curl", file=sys.stderr)
        return curl(url)


def lane(taste, now, candidates_dir="candidates"):
    """(candidates, note). A dead or garbage lane degrades to no candidates and a note for the
    vote issue rather than taking the day dark. SPEC.md §9."""
    expr = taste_query(taste)  # a bad taste.md is fatal, and the validator ran first
    try:
        items = parse(fetch(expr, now))
    except (OSError, ET.ParseError) as e:   # URLError and TimeoutError are OSErrors
        note = f"arXiv lane unreachable: {e.__class__.__name__}: {e}"
    else:
        if items:
            return items, ""
        note = "arXiv lane returned nothing usable"
    d = dead_days(candidates_dir, "arXiv")
    return [], note + (f" — {d + 1} days running with no arXiv candidates" if d else "")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--taste", default="taste.md")
    p.add_argument("--out", help="write the JSON array here (default stdout)")
    p.add_argument("--notes", help="append a degraded-lane note here, for the vote issue (§6)")
    p.add_argument("--candidates", default="candidates",
                   help="stored candidates, read only to count how long this lane has been dead")
    a = p.parse_args()
    items, note = lane(a.taste, datetime.datetime.now(datetime.timezone.utc), a.candidates)
    text = json.dumps(items, indent=1, ensure_ascii=False) + "\n"
    print(note or f"arxiv: {len(items)} candidates", file=sys.stderr)
    if note and a.notes:
        with open(a.notes, "a") as f:   # the vote issue is the only place a degraded lane shows
            f.write(" ".join(note.split()) + "\n")
    if not a.out:
        sys.stdout.write(text)
        return
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
