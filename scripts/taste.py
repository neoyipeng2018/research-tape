#!/usr/bin/env python3
"""taste.md itself: read its sections, and apply line changes to it. SPEC.md §4, §7.

Two readers need the same answers — propose-taste.py writes the monthly PR's changes, ledger.py
rebuilds the file when a box is unticked — and they have to agree to the byte, or an untick that
moved nothing still pushes. One copy of the rules lives here.
"""

OP = {"add": "added", "drop": "dropped", "rewrite": "rewritten"}


def section_lines(text, name):
    """The `- ` bullets under one heading of a taste.md held in memory."""
    out, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            inside = line.strip() == f"## {name}"
        elif inside and line.startswith("- "):
            out.append(line)
    return out


def apply(text, changes):
    """taste.md with the changes applied. An add lands at the end of its section's bullets, so
    the diff a reader reviews is the one the ledger described.

    Adds are placed before the drops and rewrites run, and never in the order the judge happened
    to return: an add anchors off the section's existing bullets, so a rewrite applied first
    would take its anchor away and land the same add a line higher. That difference is invisible
    in the monthly PR and loud in the ledger handler, where the same change set minus one box
    has to reproduce the same file.
    """
    lines = text.splitlines()
    for c in [c for c in changes if c["op"] == "add"]:
        bullets = set(section_lines(text, c["section"]))
        at = [i for i, l in enumerate(lines) if l in bullets]
        # No bullets left to follow — the heading itself is the anchor. validate-taste.sh
        # refuses an empty ## Prefer or ## Reject, so this only happens mid-apply.
        at = at or [i for i, l in enumerate(lines) if l.strip() == f'## {c["section"]}']
        lines.insert(max(at) + 1, c["line"])
    for c in [c for c in changes if c["op"] != "add"]:
        i = lines.index(c["old"])
        lines[i:i + 1] = [] if c["op"] == "drop" else [c["line"]]
    return "\n".join(lines) + "\n"
