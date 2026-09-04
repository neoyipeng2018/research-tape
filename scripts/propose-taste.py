#!/usr/bin/env python3
"""The monthly job's second half: propose the taste changes and write the PR. SPEC.md §7.

At most three line changes to `taste.md` and nothing else, each cited to the thumbed items
behind it. The 3-vote evidence bar is applied here per proposed line — the first half only
knew whether *any* line could clear it — and a change whose citations do not reach it is
malformed, not merely weak, so the judge re-rolls rather than the run shipping it.

The budget is per open PR and not per month (§7): the currently open taste PR's ledger is
handed to the judge as "already on the table", and anything it does not carry forward comes
back as `retired`, which the workflow comments on the PR before force-pushing over it.

Replay is demotion-only and scoped to the month's published items — one judge pass per change,
against `taste.md` with that one change applied. Votes only exist on published items, so a
replay can show what a rule would demote and never what it would admit; a dropped Reject line
cannot demote anything and is answered without spending a call.

Stdlib only. Writes files; the workflow owns every `gh` call and the push.
"""
import argparse, datetime, json, os, pathlib, re, sys, tempfile

import triage
from triage import Fatal, Retry, payload, run
from claim import bar
from taste import OP, apply, section_lines   # one reader of taste.md, shared with ledger.py

BUDGET = 3         # line changes per open PR. SPEC.md §7.
# Votes pointing the same way, per proposed line. Never in taste.md (§4) — a loop that can
# edit its own evidence threshold can lower it. tally-votes.py holds the same number for the
# window-wide reading; the two are one bar and move together. Named apart from claim.py's
# `bar()`, which reads the *score* bar out of taste.md.
VOTE_BAR = 3
MAX_LINE = 110     # a taste.md bullet is one line; the file is read by a human in a diff
CAP = 45           # taste.md's hard cap. validate-taste.sh enforces it; this only reports it.
SYSTEM = "You are a research-tape taste editor. Return only the requested structured output."

# §6 rule 3, again: the ledger is a task list, so a `#123` or an issue URL on a ledger line
# auto-ticks when that issue closes and fabricates consent. Ledger lines carry rule text only.
HAZARD = re.compile(r"#[0-9]|github\.com/[^ ]*/(issues|pull)/")
TASK_LINE = re.compile(r"[-*+] \[")

PROMPT = """You are editing `taste.md`, the taste file for a daily AI-in-finance research tape
read by one person. They vote 👍/👎 on the items it publishes. A month of those votes is below.

Propose AT MOST {budget} line changes to `taste.md` that those votes argue for — and nothing
they do not. Proposing fewer is normal. Proposing none is correct when the votes say nothing
clear; return an empty list and explain in `seen`.

Current ## Prefer lines:
{prefer}

Current ## Reject lines:
{reject}

Already on the table, from the open taste PR — these spend the same {budget}-change budget, so
keep the ones the votes still support and let the rest go:
{table}

Rules, all of them hard:
- Each change cites at least {bar} votes pointing the SAME way, by key, from the list below.
- `op` is "add", "drop" or "rewrite". "drop" and "rewrite" set `old` to the existing line
  VERBATIM, leading "- " and all. "add" leaves `old` empty. "drop" leaves `line` empty.
- `line` is the resulting taste.md line: one line, starts with "- ", at most {maxlen}
  characters, a rule about papers and never a reference to an issue, a PR or a person.
- `argument` is one paragraph saying what the votes show, in the second person, no lists.
- `retired` repeats VERBATIM each line already on the table you are NOT carrying
  forward, exactly as written above, with why.
- `seen` is the short list of what you noticed and did not propose: signals under the
  {bar}-vote bar, and votes that were not about taste at all.

VOTES — key · thumbs · title
{votes}
"""


def evidence(change, tally):
    """The cited items, strongest first: one row per key, the direction it was thumbed."""
    by_key = {i["key"]: i for i in tally["items"]}
    rows = []
    for key in change["evidence"]:
        e = by_key[key]
        rows.append({"key": key, "up": e["up"], "down": e["down"],
                     "day": e["days"][0], "source": e["source"]})
    rows.sort(key=lambda r: (-(r["up"] + r["down"]), r["key"]))
    return rows


def check(changes, retired, tally, taste, table):
    """Every hard rule, re-read on the way out — a change that breaks one is malformed and the
    whole proposal is re-rolled, because a shipped bad line edits what the loop reads forever."""
    keys = {i["key"]: i for i in tally["items"]}
    if len(changes) > BUDGET:
        raise Retry(f"MALFORMED_OUTPUT: {len(changes)} changes, budget is {BUDGET}")
    seen_old = set()
    for c in changes:
        where = section_lines(taste, c["section"])
        if c["op"] in ("drop", "rewrite"):
            if c["old"] not in where:
                raise Retry(f"MALFORMED_OUTPUT: no such ## {c['section']} line: {c['old'][:80]!r}")
            if c["op"] == "rewrite" and c["line"] == c["old"]:
                raise Retry(f"MALFORMED_OUTPUT: a rewrite that changes nothing: {c['old'][:80]!r}")
            if c["old"] in seen_old:
                raise Retry(f"MALFORMED_OUTPUT: two changes touch the same line: {c['old'][:80]!r}")
            seen_old.add(c["old"])
        elif c["old"]:
            raise Retry(f"MALFORMED_OUTPUT: an add carries an `old` line: {c['old'][:80]!r}")
        if c["op"] == "drop":
            if c["line"]:
                raise Retry(f"MALFORMED_OUTPUT: a drop carries a resulting line: {c['line'][:80]!r}")
        else:
            line = c["line"]
            if not line.startswith("- ") or "\n" in line or len(line) > MAX_LINE:
                raise Retry(f"MALFORMED_OUTPUT: not one '- ' bullet under {MAX_LINE} chars: "
                            f"{line[:120]!r}")
            if HAZARD.search(line):
                raise Retry(f"MALFORMED_OUTPUT: a ledger line references an issue or PR: {line}")
        if not c["argument"].strip():
            raise Retry(f"MALFORMED_OUTPUT: change {c['section']}/{c['op']} argues nothing")
        unknown = [k for k in c["evidence"] if k not in keys]
        if unknown:
            raise Retry(f"MALFORMED_OUTPUT: cites keys nobody voted on: {unknown[:5]}")
        up = sum(keys[k]["up"] for k in c["evidence"])
        down = sum(keys[k]["down"] for k in c["evidence"])
        if max(up, down) < VOTE_BAR:
            raise Retry(f"MALFORMED_OUTPUT: {c['section']}/{c['op']} cites {up}👍/{down}👎, "
                        f"the bar is {VOTE_BAR} pointing the same way")
    for r in retired:
        if r["line"] not in table:
            raise Retry(f"MALFORMED_OUTPUT: retires something never on the table: {r['line'][:80]!r}")


def parse(proc, tally, taste, table):
    got = payload(proc, "changes")
    env = json.loads(proc.stdout)                    # payload has already proved this parses
    out = env.get("structured_output") or {}
    changes = []
    for c in got:
        if not isinstance(c, dict) or not isinstance(c.get("evidence"), list):
            raise Retry(f"MALFORMED_OUTPUT: bad change {c!r}")
        changes.append({k: c.get(k, "") if k != "evidence" else list(c["evidence"])
                        for k in ("section", "op", "old", "line", "argument", "evidence")})
    retired = [r for r in (out.get("retired") or []) if isinstance(r, dict) and r.get("line")]
    seen = [str(s) for s in (out.get("seen") or []) if str(s).strip()]
    check(changes, retired, tally, taste, table)
    return changes, retired, seen


# --- the window's items ---------------------------------------------------------------------

def window(tape_dir, start, end):
    """Every item published in the window: key -> the item, plus the day it went out."""
    out, per_day = {}, {}
    for f in sorted(pathlib.Path(tape_dir).glob("*.json")):
        if not start <= f.stem <= end:
            continue
        items = json.loads(f.read_text())["items"]
        per_day[f.stem] = len(items)
        for it in items:
            out[it["key"]] = dict(it, date=f.stem)
    return out, per_day


def abstracts(cand_dir, keys):
    """The published items' abstracts, out of `candidates/` — the tape keeps four fields and an
    abstract is not one of them, and a replay is a judge pass that needs the evidence."""
    out = {}
    for f in sorted(pathlib.Path(cand_dir).glob("*.json")):
        for c in json.loads(f.read_text()):
            if c["key"] in keys and c["key"] not in out:
                out[c["key"]] = c
    return out


# --- replay ----------------------------------------------------------------------------------

def replay(change, taste_text, cands, published, per_day, threshold, schema):
    """Demotion-only, over the month's published items. Returns the line that goes under the
    change's evidence table."""
    lead = "**Replayed over the month's published items:**"
    if change["op"] == "drop" and change["section"] == "Reject":
        # A rule that only ever pushed items down cannot demote anything by leaving. The replay
        # reads published items, so this change's effect is invisible until next month's tape.
        return (f"{lead} nothing changes. Dropping a Reject line can only let *more* through, "
                "and the replay reads published items only — so this change shows up on next "
                "month's tape, not here.")
    if not cands:
        return f"{lead} no candidate records survive for these items, so nothing was replayed."
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(apply(taste_text, [change]))
        path = f.name
    try:
        ordered = sorted(cands, key=lambda c: c["key"])
        ids = set(range(1, len(ordered) + 1))
        scores = run(triage.prompt(ordered, path), schema,
                     lambda p: triage.parse(p, ids), "replay")
    finally:
        os.unlink(path)
    dropped, shrunk = [], {}
    for i, c in enumerate(ordered, 1):
        new = scores[i][0]
        if new < threshold <= c["score"]:
            item = published[c["key"]]
            dropped.append(f'*{item["title"]}* ({c["score"]} → {new})')
            shrunk[item["date"]] = shrunk.get(item["date"], per_day[item["date"]]) - 1
    if not dropped:
        return f"{lead} nothing would have dropped below the bar of {threshold}."
    days = ", ".join(f"{pretty(d)} drops to {n} item{'' if n == 1 else 's'}"
                     for d, n in sorted(shrunk.items()))
    return (f"{lead} {len(dropped)} would have dropped below the bar — "
            + ", ".join(dropped) + f". {days}.")


# --- the body ----------------------------------------------------------------------------------

def pretty(day):
    d = datetime.date.fromisoformat(day)
    return f"{d.day} {d:%b}"


def ledger_line(c):
    """Pre-ticked, rule text only. Untick to drop — `taste-ledger.yml` reads these back."""
    return f'- [x] **{c["section"]}, {OP[c["op"]]}** → *{(c["line"] or c["old"])[2:]}*'


def title(changes, tally):
    v, w = tally["votes"], tally["window"]
    return (f'Taste — {len(changes)} change{"" if len(changes) == 1 else "s"} from '
            f'{v["total"]} votes ({pretty(w["start"])} – {pretty(w["end"])})')


def body(changes, seen, tally, replays, before, after, cap, published, repo):
    v, pub, w = tally["votes"], tally["published"], tally["window"]
    span = f'{pretty(w["start"])} – {pretty(w["end"])}'
    n = len(changes)
    out = [
        f'{n} proposed change{"" if n == 1 else "s"} to `taste.md`, from **{v["total"]} votes** '
        f'({v["up"]} 👍 / {v["down"]} 👎) over {span}.',
        f'The file goes {before} → {after} lines against a hard cap of {cap}'
        + (' — a dropped line pays for an added one.' if after <= before and n > 1 else '.'),
        "",
        "**Untick anything you disagree with.** Merge takes what is still ticked; close takes "
        "nothing.",
        "",
        *[ledger_line(c) for c in changes],
        "",
        "| | |", "|---|---|",
        f"| Window | {span} · 30 days |",
        f'| Published | {pub["items"]} items over {pub["days"]} days · {pub["thin_days"]} thin '
        f'· {pub["empty_days"]} empty |',
        f'| Voted | {v["total"]} votes on {v["days"]} of {pub["days"]} days |',
        "",
    ]
    for i, (c, line) in enumerate(zip(changes, replays), 1):
        out += [f'## {i}. {c["section"]} — {OP[c["op"]]}', "", "```diff"]
        out += ([f'-{c["old"][1:]}'] if c["old"] else []) + ([f'+{c["line"][1:]}'] if c["line"] else [])
        out += ["```", "", " ".join(c["argument"].split()), "",
                "| | Item | Vote |", "|---|---|---|"]
        for r in evidence(c, tally):
            it = published.get(r["key"])
            face = "👍" if r["up"] >= r["down"] else "👎"
            title_ = (it["title"] if it else r["key"]).replace("[", r"\[").replace("]", r"\]")
            # Off the window's tape: no stored link, so the key is resolved by its own source.
            fallback = (f'https://doi.org/{r["key"]}' if r["source"].lower() == "ssrn"
                        else f'https://arxiv.org/abs/{r["key"]}')
            link = (it["link"] if it else fallback).replace(")", "%29")
            day = r["day"]
            out.append(f'| {face} | [{title_}]({link}) | '
                       f'[{pretty(day["date"])}](https://github.com/{repo}/issues/{day["issue"]}) |')
        out += ["", line, ""]
    if seen:
        out += ["## Seen, not proposed", ""] + [f"- {s}" for s in seen] + [""]
    return "\n".join(out).rstrip() + "\n"


def guard(text):
    """No ledger or table line may auto-tick. Same hazard as the vote issue (§6 rule 3)."""
    for line in text.splitlines():
        if TASK_LINE.match(line.strip()) and HAZARD.search(line):
            sys.exit(f"refusing to raise: a ledger line would auto-tick — {line}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--tally", required=True, help="tally-votes.py output")
    p.add_argument("--taste", default="taste.md")
    p.add_argument("--tape-dir", default="tape")
    p.add_argument("--candidates-dir", default="candidates")
    p.add_argument("--schema", default="schema/propose.json")
    p.add_argument("--triage-schema", default="schema/triage.json")
    p.add_argument("--open-pr", help="body of the taste PR already open, if there is one")
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    p.add_argument("--body", required=True, help="the PR body")
    p.add_argument("--title", required=True, help="the PR title, one line")
    p.add_argument("--retired", required=True, help="what this run took off the table")
    p.add_argument("--note", required=True, help="the no-change line, when nothing is proposed")
    a = p.parse_args()

    with open(a.tally) as f:
        tally = json.load(f)
    taste = open(a.taste).read()
    threshold, _ = bar(a.taste)
    w = tally["window"]
    published, per_day = window(a.tape_dir, w["start"], w["end"])

    # The ledger of the PR already open: its lines are what a new change has to beat (§7).
    table = []
    if a.open_pr and os.path.exists(a.open_pr):
        table = [l.strip() for l in open(a.open_pr) if l.strip().startswith("- [")]

    gone = "(no longer on the window's tape)"
    votes = "\n".join(
        f'{i["key"]} · {i["up"]}👍 {i["down"]}👎 · '
        f'{published[i["key"]]["title"] if i["key"] in published else gone}'
        for i in tally["items"])
    text = PROMPT.format(budget=BUDGET, bar=VOTE_BAR, maxlen=MAX_LINE,
                         prefer="\n".join(section_lines(taste, "Prefer")),
                         reject="\n".join(section_lines(taste, "Reject")),
                         table="\n".join(table) or "(nothing — no taste PR is open)",
                         votes=votes or "(no votes in the window)")
    with open(a.schema) as f:
        schema = f.read()
    try:
        changes, retired, seen = run(text, schema,
                                     lambda pr: parse(pr, tally, taste, table), "propose", SYSTEM)
    except Fatal as e:
        sys.exit(f"propose: {e}")   # no PR, nothing written (§9)

    if not changes:
        # The bar was clear but nothing is worth proposing. The first half owes this line when
        # the bar is not reached; this half owes the same line here (§7).
        n = tally["votes"]["total"]
        with open(a.note, "w") as f:
            f.write(f"*No taste change this month — {n} vote{'' if n == 1 else 's'} in the "
                    f"window, nothing worth proposing.*\n")
        print("propose: nothing worth proposing", file=sys.stderr)
        return

    with open(a.triage_schema) as f:
        triage_schema = f.read()
    cands = list(abstracts(a.candidates_dir, set(published)).values())
    replays = [replay(c, taste, cands, published, per_day, threshold, triage_schema)
               for c in changes]

    amended = apply(taste, changes)
    before, after = len(taste.splitlines()), len(amended.splitlines())
    text = body(changes, seen, tally, replays, before, after, CAP, published, a.repo)
    guard(text)

    with open(a.taste, "w") as f:
        f.write(amended)
    with open(a.body, "w") as f:
        f.write(text)
    with open(a.title, "w") as f:
        f.write(title(changes, tally) + "\n")
    with open(a.retired, "w") as f:
        for r in retired:
            # The ledger line minus its checkbox: a comment is not a ledger, and a live box in
            # a comment is one more thing that can be ticked by something other than a reader.
            line = r["line"].strip()
            line = line[line.index("]") + 1:].strip() if "]" in line[:8] else line
            f.write(f'- Retired {line} — {" ".join(str(r["why"]).split())}\n')
    print(f"propose: {len(changes)} change(s), {len(retired)} retired, "
          f"{before} → {after} lines", file=sys.stderr)


if __name__ == "__main__":
    main()
