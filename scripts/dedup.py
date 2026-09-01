#!/usr/bin/env python3
"""Identity, applied once, before judging. SPEC.md §2.

Three drops, in order: a key that has ever published (any `tape/*.json`, any age), a
fingerprint collision inside the day, and a fingerprint collision against the trailing
30 days of `candidates/*.json` — published or not. Fingerprint is the set of 4+ character
lowercase tokens in the abstract; same paper above Jaccard 0.35. Normalized title is not
part of the rule: it is strictly weaker on both real duplicate pairs.

Tape files carry no abstract, so a paper re-posted under a *new* key is caught by fingerprint
only while the original is still inside the 30-day candidates window. Storing fingerprints in
tape/ would close that; nothing measured says it is worth the permanent file growth.
"""
import argparse, datetime, glob, itertools, json, os, re, sys

THRESHOLD = 0.35   # real duplicates measure 1.000 and 0.589, the highest genuine pair 0.124
WINDOW_DAYS = 30   # matches the candidates/ prune, so the read is one directory listing
TOKEN = re.compile(r"[a-z]{4,}")
DATED = re.compile(r"(\d{4}-\d{2}-\d{2})\.json\Z")


def fp(item):
    return set(TOKEN.findall((item.get("abstract") or "").lower()))


def same(a, b):
    """Jaccard over the two fingerprints. An empty one is nobody's duplicate — the fetchers
    drop abstract-less records, but a stored candidate is not ours to trust."""
    return bool(a and b) and len(a & b) / len(a | b) > THRESHOLD


def loser(a, b):
    """arXiv survives cross-source — versioned, permanent id, free PDF, no forbidden landing
    page. Same-source falls to the lower key, the earlier posting."""
    return max((a, b), key=lambda c: (c.get("source") != "arXiv", c["key"]))["key"]


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        sys.exit(f"{path}: {e}")


def published_keys(tape_dir):
    """Every key any tape ever carried. No age cut: a paper republished a year later is still
    the paper we ran."""
    return {i["key"] for p in glob.glob(os.path.join(tape_dir, "*.json"))
            for i in load(p).get("items", [])}


def prior(candidates_dir, day):
    """Candidates from the trailing 30 days, the day itself excluded so a re-run is idempotent."""
    out = []
    for path in sorted(glob.glob(os.path.join(candidates_dir, "*.json"))):
        m = DATED.search(os.path.basename(path))
        if not m:
            continue
        d = datetime.date.fromisoformat(m.group(1))
        if day - datetime.timedelta(days=WINDOW_DAYS) <= d < day:
            out.extend(load(path))
    return out


def dedup(candidates, published, seen):
    """Three drops, in order: the ever-published key, the day's own fingerprint collisions,
    then the trailing window's. Order matters — running the published drop first is what stops
    an already-published paper from shielding a fresh copy of itself in the pairwise pass."""
    kept = {}
    for c in candidates:            # exact key first, inside the day as well as against tape/
        if c["key"] not in published:
            kept.setdefault(c["key"], c)
    fps = {k: fp(c) for k, c in kept.items()}
    seen_fps = [fp(s) for s in seen]
    drop = set()
    for a, b in itertools.combinations(kept.values(), 2):
        if same(fps[a["key"]], fps[b["key"]]):
            drop.add(loser(a, b))
    for k in kept:
        if any(same(fps[k], s) for s in seen_fps):
            drop.add(k)
    return [c for k, c in kept.items() if k not in drop]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--in", dest="src", help="the day's candidates (default stdin)")
    p.add_argument("--out", help="write the JSON array here (default stdout)")
    p.add_argument("--tape-dir", default="tape")
    p.add_argument("--candidates-dir", default="candidates")
    p.add_argument("--date", help="the day being built, YYYY-MM-DD (default today, UTC)")
    a = p.parse_args()
    day = (datetime.date.fromisoformat(a.date) if a.date
           else datetime.datetime.now(datetime.timezone.utc).date())
    candidates = load(a.src) if a.src else json.load(sys.stdin)
    kept = dedup(candidates, published_keys(a.tape_dir), prior(a.candidates_dir, day))
    print(f"dedup: {len(kept)} candidates, {len(candidates) - len(kept)} dropped",
          file=sys.stderr)
    text = json.dumps(kept, indent=1, ensure_ascii=False) + "\n"
    if not a.out:
        sys.stdout.write(text)
        return
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
