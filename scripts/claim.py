#!/usr/bin/env python3
"""Pass 2 — selection and the claim, then the day's tape file. SPEC.md §3.3-3.4.

The bar is `threshold` and `cap` out of taste.md, never a constant here: score >= threshold,
then the cap. One bar and one lane list — no per-source floor and no per-source bar, because
over five real days arXiv cleared 7 twice as often as SSRN and took 13 of 20 slots anyway.

The judge runs once, over survivors only. The hard rules in the prompt are the product: without
them 4 of 6 sentences came back as semicolon-joined summaries. They are re-checked here on the
way out, so a sentence that breaks them is malformed and retried rather than published.

A day where nothing clears the bar writes an empty tape file. A thin day publishes under the cap.
Filler is never written to fill the page.
"""
import argparse, datetime, json, os, re, sys

from triage import Fatal, Retry, block, payload, run, same_ids   # the judge plumbing, from pass 1

# The rules below are also prose inside PROMPT, where the judge reads them; both say 25 words and
# the same five openers, and a change to one is a change to both.
WORDS = 25
OPENERS = ("researchers", "this paper", "the authors", "a novel", "a framework")
HYPE = ("novel", "groundbreaking", "cutting-edge", "revolutionary", "powerful", "robust")
SYSTEM = "You are a research-tape claim writer. Return only the requested structured output."

# SPEC.md §3.3 verbatim, except the output block: the spec wrote JSONL, which cannot come back
# through --json-schema, so pass 1's `{"scores": [...]}` envelope shape is used instead. §3.3 also
# passes the abstract whole — on a survivor it is the evidence the claim has to be supported by.
PROMPT = """For each paper below, write the single sentence that goes on a daily research tape
read by a quant/ML practitioner. The sentence IS the product.

It must ASSERT A CLAIM — something a reader could disagree with — not summarise the paper.
If you cannot find a claim in the abstract, say plainly what is missing; that is also a claim.

Hard rules:
- One sentence, 25 words maximum.
- NO SEMICOLONS. If you reach for one, you are summarising two things instead of claiming one.
- Never open with "researchers", "this paper", "the authors", "a novel", "a framework".
- No hype words: novel, groundbreaking, cutting-edge, revolutionary, powerful, robust.
- Claim only what the abstract supports. Conditional finding, conditional sentence.

Return one entry per paper, and nothing else:
{{"claims": [{{"id": <int>, "sentence": "<the sentence>"}}]}}

PAPERS
{papers}
"""


def bar(path):
    """threshold and cap out of taste.md ## Bar. validate-taste.sh has already refused anything
    else; this reads, it does not re-validate."""
    out = dict(l.split(":", 1) for l in block(path, "Bar") if ":" in l)
    out = {k.strip(): v.strip() for k, v in out.items()}
    try:
        return int(out["threshold"]), int(out["cap"])
    except (KeyError, ValueError):
        sys.exit(f"{path}: ## Bar needs integer 'threshold:' and 'cap:' lines")


def survivors(candidates, threshold, cap):
    """The bar, then the cap, in publish order — score descending, then key, re-established here
    so the cap cuts the tail of a genuine tie the same way whatever order the file arrives in."""
    cleared = sorted((c for c in candidates if c["score"] >= threshold),
                     key=lambda c: (-c["score"], c["key"]))
    return cleared[:cap]


def prompt(papers):
    lines = []
    for i, c in enumerate(papers, 1):
        abstract = re.sub(r"\s+", " ", c.get("abstract") or "").strip()
        lines.append(f"[{i}] ({c['source']}) {c['title']}\n{abstract}")
    return PROMPT.format(papers="\n\n".join(lines))


def check(sentence):
    """The hard rules, re-read on the way out. A sentence that breaks one is malformed: the rules
    are what make the sentence a claim rather than a summary.

    A second sentence is a stop after a whole word, then a capital: "U.S. equities", "et al. 2026"
    and "Dr. Chen" break on an initial or a short abbreviation and stay one sentence.
    """
    if ";" in sentence:
        return "semicolon"
    if re.search(r"[^\s.]{3,}[.?!]\s+[\"(\[]*[A-Z]", sentence):
        return "more than one sentence"
    if len(sentence.split()) > WORDS:
        return f"{len(sentence.split())} words, max {WORDS}"
    low = sentence.lower()
    if low.startswith(OPENERS):
        return "banned opener"
    if any(re.search(rf"\b{re.escape(w)}\b", low) for w in HYPE):
        return "hype word"
    return ""


def parse(proc, ids):
    """Pass 2's entries: one sentence per surviving paper, every hard rule re-checked."""
    got = payload(proc, "claims")
    out = {}
    for c in got:
        if not (isinstance(c, dict) and isinstance(c.get("id"), int)
                and isinstance(c.get("sentence"), str) and c["sentence"].strip()):
            raise Retry(f"MALFORMED_OUTPUT: bad entry {c!r}")
        sentence = " ".join(c["sentence"].split())
        bad = check(sentence)
        if bad:
            # Retried, not dropped: a rule-breaking sentence is a summary, and a summary on the
            # tape is worse than a short tape. Three clean re-rolls of the whole batch, then the
            # day goes dark like any other MALFORMED_OUTPUT (§9).
            raise Retry(f"MALFORMED_OUTPUT: sentence {c['id']} breaks a hard rule ({bad}): "
                        f"{sentence[:120]}")
        out[c["id"]] = sentence
    same_ids(out, ids, "written")
    return out


def claims(papers, schema):
    ids = set(range(1, len(papers) + 1))
    written = run(prompt(papers), schema, lambda p: parse(p, ids), "claim", SYSTEM)
    return [{"key": c["key"], "source": c["source"], "link": c["link"], "title": c["title"],
             "claim": written[i]} for i, c in enumerate(papers, 1)]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--in", dest="src", help="the day's scored candidates (default stdin)")
    p.add_argument("--tape-dir", default="tape")
    p.add_argument("--taste", default="taste.md")
    p.add_argument("--schema", default="schema/claim.json")
    p.add_argument("--date", help="the day being built, YYYY-MM-DD (default today, UTC)")
    a = p.parse_args()
    day = a.date or datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    threshold, cap = bar(a.taste)
    with (open(a.src) if a.src else sys.stdin) as f:
        candidates = json.load(f)
    papers = survivors(candidates, threshold, cap)
    items = []
    if papers:
        with open(a.schema) as f:
            schema = f.read()
        try:
            items = claims(papers, schema)
        except Fatal as e:
            sys.exit(f"claim: {e}")   # dark day: write nothing, commit nothing (§9)
    print(f"claim: {len(items)} published of {len(candidates)} scanned"
          f" (bar {threshold}, cap {cap})", file=sys.stderr)
    out = os.path.join(a.tape_dir, f"{day}.json")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w") as f:
        json.dump({"date": day, "scanned": len(candidates), "items": items}, f,
                  indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
