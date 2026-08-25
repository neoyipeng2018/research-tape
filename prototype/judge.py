#!/usr/bin/env python3
"""PROTOTYPE, throwaway. Two-pass judge over candidates.json via `claude -p --model haiku`."""
import json, os, re, subprocess, sys, textwrap

TASTE_F = sys.argv[1] if len(sys.argv) > 1 else "prototype/taste.md"
OUT_F = sys.argv[2] if len(sys.argv) > 2 else "prototype/scored.json"
C = json.load(open("prototype/candidates.json"))["candidates"]
TASTE = open(TASTE_F).read()
PREFER = TASTE.split("## Prefer")[1].split("## Reject")[0].strip()
REJECT = TASTE.split("## Reject")[1].split("## Bar")[0].strip()

def claude(prompt):
    env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
    r = subprocess.run(["claude", "-p", "--model", "haiku", "--output-format", "json"],
                       input=prompt, capture_output=True, text=True, env=env, timeout=900)
    out = json.loads(r.stdout)
    if out.get("api_error_status"):
        sys.exit(f"api error: {out}")
    return out["result"], out.get("usage", {}), out.get("duration_ms")

def block(c, with_abs=True):
    a = textwrap.shorten(c["abstract"], 900, placeholder=" …") if with_abs else ""
    return f"[{c['id']}] ({c['source']}) {c['title']}\n{a}"

# --- PASS 1: triage everything -------------------------------------------------
p1 = f"""You are the judge for a daily AI-in-finance research tape read by one person: a
quant/ML practitioner who builds LLM systems over financial text and cares whether a paper
changes what they would do next week.

Score EVERY candidate below 0-10 on how much it deserves that person's attention today.

They PREFER:
{PREFER}

They REJECT:
{REJECT}

Anchor the scale:
0-2 off-topic or content-free. 3-4 on-topic but adds nothing. 5-6 solid, competent, forgettable.
7-8 they would want to know this exists. 9-10 they would stop and read it today.

Be a hard marker. Most papers on most days are 5-6; a 7 is a real recommendation you are
spending their attention on. Judge only from title and abstract; do not credit claims you
cannot see evidence for.

Output one JSON object per line, no other text, no markdown fence:
{{"id": <int>, "score": <int 0-10>, "why": "<max 12 words, the reason for the score>"}}

CANDIDATES
{chr(10).join(block(c) for c in C)}
"""
res, usage, ms = claude(p1)
scores = {}
for line in res.splitlines():
    line = line.strip().strip("`")
    if line.startswith("{"):
        try:
            o = json.loads(line); scores[o["id"]] = o
        except Exception: pass
print(f"pass1: {len(scores)}/{len(C)} scored  {ms}ms  in={usage.get('input_tokens')} out={usage.get('output_tokens')}", file=sys.stderr)

for c in C:
    c.update({k: v for k, v in scores.get(c["id"], {}).items() if k != "id"})

# --- PASS 2: why-it-matters for survivors --------------------------------------
TH, CAP = 7, 6
surv = sorted([c for c in C if c.get("score", 0) >= TH], key=lambda c: -c["score"])[:CAP]
if surv:
    p2 = f"""For each paper below, write the single sentence that goes on a daily research tape
read by a quant/ML practitioner. The sentence IS the product.

It must ASSERT A CLAIM — something a reader could disagree with — not summarise the paper.
If you cannot find a claim in the abstract, say plainly what is missing; that is also a claim.

Hard rules:
- One sentence, 25 words maximum.
- NO SEMICOLONS. If you reach for one, you are summarising two things instead of claiming one.
- Never open with "researchers", "this paper", "the authors", "a novel", "a framework".
- No hype words: novel, groundbreaking, cutting-edge, revolutionary, powerful, robust.
- Claim only what the abstract supports. Conditional finding, conditional sentence.

Output one JSON object per line, no other text:
{{"id": <int>, "sentence": "<the sentence>"}}

PAPERS
{chr(10).join(block(c) for c in surv)}
"""
    res2, usage2, ms2 = claude(p2)
    for line in res2.splitlines():
        line = line.strip().strip("`")
        if line.startswith("{"):
            try:
                o = json.loads(line)
                next(c for c in C if c["id"] == o["id"])["sentence"] = o["sentence"]
            except Exception: pass
    print(f"pass2: {len(surv)} survivors  {ms2}ms  out={usage2.get('output_tokens')}", file=sys.stderr)

json.dump(C, open(OUT_F, "w"), indent=1)
