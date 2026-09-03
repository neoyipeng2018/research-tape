#!/usr/bin/env python3
"""The body of the daily vote issue. SPEC.md §6.

Two boxes an item, never pre-ticked, because the loop needs three states: liked, disliked,
didn't look. Opened every day the loop runs — a quiet day still opens one, since the issue
is also the heartbeat and the status surface for degraded lanes.

Stdlib only. Writes the body to stdout; the workflow redirects it into a file and hands
that to `gh issue create --body-file`.
"""
import argparse, json, re, sys

# §6 rule 3: a task-list line referencing an issue auto-ticks when that issue closes and
# fabricates a vote. Paper links live in the heading, which is not a task list.
HAZARD = re.compile(r"#[0-9]|github\.com/[^ ]*/(issues|pull)/")
TASK_LINE = re.compile(r"[-*+] \[")   # §6 rule 4: `*` and `+` render as task lists too


def vote_lines(item):
    """The two boxes. The key rides a *trailing* comment — a leading one destroys the
    checkbox — and the form is the documented `- [ ] `, space and all (§6 rules 1-2)."""
    key = f'{item["source"].lower()}:{item["key"]}'
    return [f"- [ ] {face} <!--v:{d}:{key}-->"
            for d, face in (("up", "👍 more like this"), ("down", "👎 less like this"))]


def body(tape, notes):
    n, scanned = len(tape["items"]), tape["scanned"]
    out = [f'# Research Tape — {tape["date"]}', ""]
    if not tape["items"]:
        out += [f"Nothing cleared the bar today — 0 of {scanned} scanned. No votes to cast."]
    else:
        out += [f"{n} of {scanned} scanned. Two boxes an item: tick 👍 or 👎, or leave both "
                "empty — that reads as *didn't look*.", ""]
        for it in tape["items"]:
            title = it["title"].replace("[", r"\[").replace("]", r"\]")
            link = it["link"].replace(")", "%29")   # a bare ) would close the heading link
            out += [f"### [{title}]({link})", *vote_lines(it), ""]
    if notes:
        out += ["---", ""] + list(notes)
    return "\n".join(out).rstrip() + "\n"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--tape", required=True, help="tape/YYYY-MM-DD.json")
    p.add_argument("--notes", help="status lines to append, one per line; missing is fine")
    a = p.parse_args()

    with open(a.tape) as f:
        tape = json.load(f)
    notes = []
    if a.notes:
        try:
            with open(a.notes) as f:
                notes = [l.strip() for l in f if l.strip()]
        except FileNotFoundError:
            pass   # no degraded lane, no file
    text = body(tape, notes)

    for line in text.splitlines():
        if TASK_LINE.match(line) and HAZARD.search(line):
            sys.exit(f"refusing to open: a vote line would auto-tick — {line}")

    print(f"vote issue: {len(tape['items'])} items, {len(notes)} note(s)", file=sys.stderr)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
