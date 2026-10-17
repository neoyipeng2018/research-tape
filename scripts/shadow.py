#!/usr/bin/env python3
"""The shadow week (docs/adr/0002). Every free model in CHAIN judges the day Haiku has already
judged — triage, the bar, claims — and nothing it says is published. A model that fails is
recorded with its reason and the next one runs. The file is evidence for choosing the judge
chain and nothing in the loop reads it back; delete this script at cutover.
"""
import argparse, json, os, sys

import claim, triage

# Vendors interleaved, so one vendor pulling its free tier never takes two links in a row.
CHAIN = ["nvidia/nemotron-3-super-120b-a12b:free", "google/gemma-4-31b-it:free",
         "nvidia/nemotron-3.5-super-vl:free", "google/gemma-4-26b-a4b-it:free"]


def judge(model, candidates, taste, triage_schema, claim_schema):
    triage.MODEL = model   # claim.run is triage.run, so both passes go to this model
    try:
        scored = triage.triage(candidates, taste, triage_schema)
        papers = claim.survivors(scored, *claim.bar(taste))
        items = claim.claims(papers, claim_schema) if papers else []
    except Exception as e:   # ponytail: evidence only — one model's crash never skips the next
        return {"error": f"{type(e).__name__}: {e}"}
    return {"scores": {c["key"]: c["score"] for c in scored},
            "claims": {i["key"]: i["claim"] for i in items}}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--in", dest="src", required=True, help="the day's candidates file")
    p.add_argument("--out", required=True)
    p.add_argument("--taste", default="taste.md")
    a = p.parse_args()
    with open(a.src) as f:
        candidates = json.load(f)
    with open("schema/triage.json") as f, open("schema/claim.json") as g:
        schemas = f.read(), g.read()
    out = {}
    for model in CHAIN if candidates else []:
        out[model] = judge(model, candidates, a.taste, *schemas)
        r = out[model]
        print(f"shadow: {model}: " + (r["error"] if "error" in r else
              f"{len(r['scores'])} scored, {len(r['claims'])} would publish"), file=sys.stderr)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
