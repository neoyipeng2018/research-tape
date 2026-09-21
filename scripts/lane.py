#!/usr/bin/env python3
"""What a lane is, and when one has been dead long enough to shout about. SPEC.md §1, §9.

A lane is a corpus, not a transport: "arXiv" names the papers, not the host they arrived
through (docs/adr/0001). So a lane is dead only when nothing from that corpus reached the
day's candidates — however it was fetched.

Both fetchers degrade to zero candidates and exit 0, which is right for a blip and wrong
for an outage: arXiv answered the runner 406 for ten days in September 2026 and the only
report was a line in a vote issue nobody opened. The streak here is what makes the
difference visible, and run as a script this is the daily workflow's last step — after the
tape is pushed and the vote issue is open, so a degraded day still publishes before the
run goes red.
"""
import argparse, json, os, sys

LANES = ("arXiv", "SSRN")   # the `source` written on every candidate, by both fetchers
MAX_DEAD = 3   # days a lane may be dead before the run fails. One number for every lane:
               # at this streak the agreed response is to build the lane a second transport.


def dead_days(candidates_dir, source, today=None):
    """How many days running this lane has produced nothing, counted off the stored
    candidates, newest first. A one-day blip and a ten-day outage read identically without
    it. Bounded by the 30-day prune.

    `today` is the day being built: the fetchers call this before writing it and so count
    only history, while the workflow's final check calls it after and counts today too.
    """
    n = 0
    try:
        days = sorted(os.listdir(candidates_dir), reverse=True)
    except OSError:
        return 0
    for name in days:
        if not name.endswith(".json") or (today and name == f"{today}.json"):
            continue
        try:
            with open(os.path.join(candidates_dir, name)) as f:
                rows = json.load(f)
        except (OSError, ValueError):
            break   # an unreadable day breaks the chain rather than extending it
        if any(r.get("source") == source for r in rows):
            break
        n += 1
    return n


def contributed(candidates):
    """The lanes that actually put a candidate into this day, in LANES order. Written onto
    the tape so the archive records which days drew from a thinner pool than taste intends
    — the taste ledger argues from votes, and votes cast on a degraded day came from half
    the intended pool."""
    seen = {c.get("source") for c in candidates}
    return [l for l in LANES if l in seen]


def missing(tape):
    """The lanes that were down on a published day, read back off its tape. A tape written
    before the `lanes` field existed says nothing rather than guessing: those days were not
    observed, and a backfill would be a claim about them we cannot make."""
    lanes = tape.get("lanes")
    return [l for l in LANES if l not in lanes] if lanes is not None else []


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--candidates", default="candidates")
    p.add_argument("--max-dead", type=int, default=MAX_DEAD)
    a = p.parse_args()
    bad = False
    for source in LANES:
        d = dead_days(a.candidates, source)
        print(f"{source}: {d} day(s) with no candidates", file=sys.stderr)
        if d >= a.max_dead:
            # ::error:: puts it on the run summary; the non-zero exit is what actually mails.
            print(f"::error::{source} lane dead {d} days running — the tape has been "
                  f"publishing from a thinner pool than taste intends", file=sys.stderr)
            bad = True
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
