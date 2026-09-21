#!/usr/bin/env python3
"""The arXiv lane: one call, trailing 7 days, candidates out. SPEC.md §1.1.

The query lives in taste.md (## Queries, the `arxiv:` line), never here. One request per
run, so the 1 req/3s ToU limit needs no pacing. An unreachable or garbage arXiv degrades
to zero candidates and exit 0 — the day publishes from Crossref alone (§9).
"""
import argparse, datetime, json, os, re, sys, urllib.parse, urllib.request
import xml.etree.ElementTree as ET

API = "https://export.arxiv.org/api/query"  # http:// 301s
ATOM = "{http://www.w3.org/2005/Atom}"
UA = "research-tape/0.1 (https://github.com/neoyipeng2018/research-tape)"
# The runner has been answered 406 since 2026-09-11 while this exact request succeeds from a
# residential IP, so the suspect is arXiv's edge, not the query. urllib sends no Accept at all
# and 406 *is* a content-negotiation refusal, which makes this the one-line thing to rule out
# before concluding the runner's IP is blocked. If the 406 survives this, it was never the header.
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
    since = now - datetime.timedelta(days=WINDOW_DAYS)
    stamp = "%Y%m%d%H%M"
    return f"({expr}) AND submittedDate:[{since.strftime(stamp)} TO {now.strftime(stamp)}]"


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


def fetch(expr, now):
    url = API + "?" + urllib.parse.urlencode({
        "search_query": search_query(expr, now),
        "max_results": 2000,
    })
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def dead_days(candidates_dir):
    """How many days running this lane has already produced nothing, counted off the stored
    candidates. A one-day blip and the ten-day outage of September 2026 leave identical notes
    otherwise, and the note is the only place either one is ever reported (§9). Bounded by the
    30-day prune, and today's file does not exist yet when this runs."""
    n = 0
    try:
        days = sorted(os.listdir(candidates_dir), reverse=True)
    except OSError:
        return 0
    for name in days:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(candidates_dir, name)) as f:
                rows = json.load(f)
        except (OSError, ValueError):
            break   # an unreadable day breaks the chain rather than extending it
        if any(r.get("source") == "arXiv" for r in rows):
            break
        n += 1
    return n


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
    d = dead_days(candidates_dir)
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
