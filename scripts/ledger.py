#!/usr/bin/env python3
"""The untick handler: the taste PR's ledger is the review surface. SPEC.md §7.

Reviewing a taste change is unticking a box, never editing a diff. This reads the PR body as
it now stands, rebuilds `taste.md` from the PR's *base* plus only the still-ticked changes, and
says what moved. Rebuilding from the base rather than patching the branch is what makes
re-ticking restore a change: the branch's current `taste.md` is an output, never state.

The ledger carries rule text only (§7), so it cannot say which line a *rewrite* replaced — the
`old`/`new` pair comes out of that change's ```diff block, which propose-taste.py wrote from the
same change. The ledger's i-th box is the i-th `## i.` section, and a body where those two
disagree — a body with no ledger at all included — is not a body this can act on: it exits
non-zero and pushes nothing, because a wiped body is an accident and not a review.

Stdlib only. Writes files; the workflow owns the push and every `gh` call.
"""
import argparse, pathlib, re, sys

from taste import OP, apply     # one reader of taste.md, shared with propose-taste.py

# §6 rule 4, the same liberal parser the vote issue is read with: `-`/`*`/`+`, either case of x.
BOX = re.compile(r"[-*+] \[([ xX])\] \*\*(\w+), (\w+)\*\*")
HEAD = re.compile(r"## (\d+)\. (\w+) — (\w+)$")
UNOP = {v: k for k, v in OP.items()}     # "added" -> "add"


def fence(lines, i):
    """The ```diff block under the change heading at `lines[i]`."""
    start = next((j for j in range(i + 1, len(lines)) if lines[j].strip() == "```diff"), None)
    if start is None:
        sys.exit(f"ledger: no diff block under {lines[i].strip()!r}")
    end = next((j for j in range(start + 1, len(lines)) if lines[j].strip() == "```"), None)
    if end is None:
        sys.exit(f"ledger: unterminated diff block under {lines[i].strip()!r}")
    return lines[start + 1:end]


def ledger(body):
    """The PR body as (still-ticked, change) pairs, in ledger order."""
    lines = body.splitlines()
    boxes = [m.groups() for m in (BOX.match(l.strip()) for l in lines) if m]
    changes = []
    for i, l in enumerate(lines):
        m = HEAD.match(l.strip())
        if not m:
            continue
        diff = fence(lines, i)
        # `-` + old[1:] and `+` + line[1:] over lines that already start "- ", so the old line
        # comes back verbatim and the new one only needs its marker put back.
        old = next((d for d in diff if d.startswith("- ")), "")
        new = next(("-" + d[1:] for d in diff if d.startswith("+ ")), "")
        changes.append({"n": m.group(1), "section": m.group(2), "op": UNOP.get(m.group(3), ""),
                        "old": old, "line": new})
    # An empty body agrees with itself — 0 boxes against 0 sections — and would rebuild the base
    # file and push it. A ledger nobody can see is not a ledger everybody unticked.
    if not boxes:
        sys.exit("ledger: no ledger in the body — nothing to read")
    if len(boxes) != len(changes):
        sys.exit(f"ledger: {len(boxes)} ledger box(es) against {len(changes)} change section(s)")
    out = []
    for i, ((box, section, op), c) in enumerate(zip(boxes, changes), 1):
        if c["n"] != str(i) or c["section"] != section or UNOP.get(op) != c["op"]:
            sys.exit(f"ledger: box {i} ({section}, {op}) does not match section "
                     f'{c["n"]}. {c["section"]} — {OP.get(c["op"], "?")}')
        if not c["op"] or (c["op"] == "add" and c["old"]) or (c["op"] == "drop" and c["line"]):
            sys.exit(f"ledger: change {i} is not a readable {op}")
        out.append((box.lower() == "x", c))
    return out


def carried(c, lines):
    """Whether the branch's taste.md currently carries this change."""
    return c["old"] not in lines if c["op"] == "drop" else c["line"] in lines


def note(moved):
    """What the PR is told: the boxes whose state the file did not match."""
    out = ["Ledger edited — `taste.md` now carries only the still-ticked changes, force-pushed "
           "over the branch.", ""]
    if not moved:
        # The ledger did not move but the file did — taste.md was edited on the branch by hand.
        # The ledger is the review surface, so the file is rebuilt from it and this says so.
        out.append("- The file no longer matched the ledger and was rewritten from it.")
    for ticked, c in moved:
        out.append(f'- **{"Restored" if ticked else "Dropped"}: {c["section"]}, {OP[c["op"]]}** — '
                   f'*{(c["line"] or c["old"])[2:]}*')
    out += ["", "Merge takes what is still ticked; close takes nothing."]
    return "\n".join(out) + "\n"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--body", required=True, help="the PR body as it now stands")
    p.add_argument("--base", required=True, help="taste.md as it is on the PR's base branch")
    p.add_argument("--taste", default="taste.md", help="rewritten in place when the ledger moved")
    p.add_argument("--comment", required=True, help="what was dropped; empty when nothing moved")
    a = p.parse_args()

    # Emptied first: the workflow reads emptiness as "nothing moved", and a body that does not
    # parse has to read that way too rather than leaving a stale comment behind.
    out = pathlib.Path(a.comment)
    out.write_text("")
    boxes = ledger(pathlib.Path(a.body).read_text())
    current = pathlib.Path(a.taste).read_text()

    amended = apply(pathlib.Path(a.base).read_text(), [c for ticked, c in boxes if ticked])
    if amended == current:
        print("ledger: unchanged — nothing to push", file=sys.stderr)
        return
    moved = [(t, c) for t, c in boxes if t != carried(c, current.splitlines())]
    pathlib.Path(a.taste).write_text(amended)
    out.write_text(note(moved))
    kept = sum(1 for t, _ in boxes if t)
    print(f"ledger: {kept} of {len(boxes)} change(s) still ticked, {len(moved)} moved",
          file=sys.stderr)


if __name__ == "__main__":
    main()
