#!/usr/bin/env python3
"""The monthly job's first half: read the votes and say what they add up to. SPEC.md §6-§7.

A rolling 30-day window of `vote`-labelled issues, read by label listing and never by search
(1,000/hr against 30/min), one fetch per issue body. There is no consumed marker anywhere —
a ticked box carries no timestamp, so the window *is* the mechanism: reruns are idempotent
and a late tick inside the window still counts. A tick on an issue older than the window is
never counted, which is the accepted cost.

The 3-vote evidence bar lives here and never in taste.md — a loop that can edit its own
evidence threshold can lower it. §7 applies it per proposed line, and no line's evidence can
be larger than the window's votes in that direction, so what this half decides is the half it
can: fewer than three either way means no line could clear, and the run says so out loud. The
proposing half owns the per-line reading, and owes the same line when it proposes nothing.

Stdlib only. Reads the issues as JSON — the workflow does the `gh` calls, because fetching is
where the token lives and counting is what a test can reach.
"""
import argparse, datetime, json, pathlib, re, sys

from claim import bar          # ## Bar out of taste.md, one reader for all three scripts

BAR = 3            # votes pointing the same way. SPEC.md §4: never in taste.md.
WINDOW_DAYS = 30   # the candidates/ retention, and prune-candidates.sh's boundary

# §6 rule 4: the parser stays liberal — `-`/`*`/`+`, either case of `x`. The key rides a
# *trailing* comment, so the box and the key sit at the two ends of the line.
VOTE = re.compile(r"^\s*[-*+] \[([ xX])\] .*<!--v:(up|down):([^:]+):(.+?)-->\s*$")
TITLE_DATE = re.compile(r"(\d{4}-\d{2}-\d{2})")


def ticks(body):
    """Every ticked box in one issue body, as (direction, source, key). An empty box is not a
    vote and neither is a line without a key comment."""
    out = []
    for line in (body or "").splitlines():
        m = VOTE.match(line)
        if m and m.group(1) in "xX":
            out.append((m.group(2), m.group(3), m.group(4)))
    return out


def day_of(issue):
    """The tape date the issue votes on — the date in its title, which is the one basis the
    window uses, so the days counted and the tape files read are the same days. Creation is
    the fallback and is a day behind by design: the run fires 22:00 UTC and the tape it
    carries is dated the next SGT morning."""
    m = TITLE_DATE.search(issue.get("title") or "")
    return m.group(1) if m else issue["created_at"][:10]


def published(tape_dir, start, end, day_cap):
    """Items published in the window, and the shape of the days — thin, empty, full."""
    days, items, thin, empty = 0, 0, 0, 0
    for f in sorted(tape_dir.glob("*.json")):
        if not start <= f.stem <= end:
            continue
        n = len(json.loads(f.read_text())["items"])
        days, items = days + 1, items + n
        empty += n == 0
        thin += 0 < n < day_cap
    return {"days": days, "items": items, "thin_days": thin, "empty_days": empty}


def tally(issues, tape_dir, start, end, day_cap):
    votes, per_key, carrying, newest = {"up": 0, "down": 0}, {}, set(), None
    for issue in sorted(issues, key=lambda i: (day_of(i), i["number"])):
        day = day_of(issue)
        if not start <= day <= end:     # both ends, so a rerun over an older window stays in it
            continue
        newest = issue["number"]
        for direction, source, key in ticks(issue["body"]):
            votes[direction] += 1
            carrying.add(issue["number"])
            e = per_key.setdefault(key, {"key": key, "source": source, "up": 0, "down": 0,
                                         "days": []})
            e[direction] += 1
            e["days"].append({"date": day, "issue": issue["number"]})

    total = votes["up"] + votes["down"]
    return {
        "window": {"start": start, "end": end},
        "published": published(tape_dir, start, end, day_cap),
        "votes": {**votes, "total": total, "days": len(carrying)},
        "items": sorted(per_key.values(), key=lambda e: (-(e["up"] + e["down"]), e["key"])),
        "clears_bar": max(votes["up"], votes["down"]) >= BAR,
        # The day's vote issue, where the no-change line goes. Newest in the window, whether or
        # not anyone ticked it — an unvoted month is exactly when the line has to be said.
        "note_issue": newest,
    }


def note(t):
    """The one line that goes on the day's vote issue when nothing is proposed. Silence makes
    a thinking loop and a broken loop look identical (§7)."""
    n = t["votes"]["total"]
    return (f"*No taste change this month — {n} vote{'' if n == 1 else 's'} in the window, "
            f"nothing reached the {BAR}-vote bar.*")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--issues", required=True,
                   help="JSON array of vote issues: number, title, created_at, body")
    p.add_argument("--tape-dir", default="tape")
    p.add_argument("--taste", default="taste.md")
    p.add_argument("--today", help="window end, YYYY-MM-DD; defaults to the SGT date daily.yml stamps")
    p.add_argument("--note", help="write the no-change line here when nothing clears the bar")
    a = p.parse_args()

    end = a.today or str(datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).date())
    start = str(datetime.date.fromisoformat(end) - datetime.timedelta(days=WINDOW_DAYS))

    with open(a.issues) as f:
        issues = json.load(f)
    t = tally(issues, pathlib.Path(a.tape_dir), start, end, bar(a.taste)[1])

    v, pub = t["votes"], t["published"]
    print(f'votes {v["total"]} ({v["up"]}👍/{v["down"]}👎) over {v["days"]} day(s); '
          f'{pub["items"]} item(s) published on {pub["days"]} day(s), '
          f'{pub["thin_days"]} thin, {pub["empty_days"]} empty; '
          f'bar {"cleared" if t["clears_bar"] else "not reached"}', file=sys.stderr)
    if a.note and not t["clears_bar"]:
        with open(a.note, "w") as f:
            f.write(note(t) + "\n")
    json.dump(t, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
