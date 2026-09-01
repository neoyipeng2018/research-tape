#!/usr/bin/env python3
"""Pass 1 — triage. Every deduped candidate scored 0-10, three runs, median wins. SPEC.md §3.1-3.2.

One `claude -p` call per run for all candidates, not one per candidate: 60 candidates is ~24K
tokens and ~110s wall clock, of which ~89s is time to first token — normal, not a hang. The
identical prompt runs three times and the median score wins, which removes outlier errors (a
non-finance paper published in 1 of 6 single runs and 0 of 20 median triples); it does not
stabilise the ranking, and is not meant to.

Prefer and Reject are read verbatim out of taste.md. The schema constrains shape, not
completeness, so the returned id set is compared against the input set and a mismatch is
malformed. Every candidate is written out with its score, cleared or not.

Failure branches on the JSON envelope and never on `subtype`, which still reads "success" on an
auth failure (§9): AUTH_DEAD and LIMITS_EXHAUSTED never retry, CLI_HANG and MALFORMED_OUTPUT
retry three times. No cost or token logic — `total_cost_usd` is a client-side estimate and
`input_tokens` reported 9 on a 25K-token prompt.
"""
import argparse, json, os, re, statistics, subprocess, sys

RUNS = 3          # median of three
ATTEMPTS = 3      # per run, on CLI_HANG and MALFORMED_OUTPUT only — the rest never retry
TIMEOUT = 600     # seconds; ~110s is a normal call, so this is a hang, not a slow day
ABSTRACT = 900    # chars per candidate, whitespace-collapsed
SYSTEM = "You are a research-tape triage classifier. Return only the requested structured output."
AUTH = re.compile(r"authenticat|expired|oauth|invalid api key|log ?in", re.I)
LIMITS = re.compile(r"\blimit|resets|balance", re.I)

PROMPT = """You are the judge for a daily AI-in-finance research tape read by one person: a
quant/ML practitioner who builds LLM systems over financial text and cares whether a
paper changes what they would do next week.

Score EVERY candidate below 0-10 on how much it deserves that person's attention today.

They PREFER:
{prefer}

They REJECT:
{reject}

Anchor the scale:
0-2 off-topic or content-free. 3-4 on-topic but adds nothing. 5-6 solid, competent,
forgettable. 7-8 they would want to know this exists. 9-10 they would stop and read it today.

Be a hard marker. Most papers on most days are 5-6; a 7 is a real recommendation you are
spending their attention on. Judge only from title and abstract; do not credit claims you
cannot see evidence for.

Return one entry per candidate, and nothing else:
{{"scores": [{{"id": <int>, "score": <int 0-10>, "why": "<max 12 words, the reason for the score>"}}]}}

CANDIDATES
{candidates}
"""


class Fatal(Exception):
    """AUTH_DEAD or LIMITS_EXHAUSTED. Dark day, no retry — a token does not heal in 30s."""


class Retry(Exception):
    """CLI_HANG or MALFORMED_OUTPUT. Three attempts, then the day goes dark."""


def block(path, name):
    """The lines under one taste.md heading. Shared with pass 2's ## Bar reader; validate-taste.sh
    has already refused a file shaped any other way."""
    out, inside = [], False
    with open(path) as f:
        for line in f:
            if line.startswith("## "):
                inside = line.strip() == f"## {name}"
            elif inside:
                out.append(line.rstrip())
    return out


def section(path, name):
    """The `- ` bullets under one heading, verbatim — the judge reads taste.md's words, not a
    paraphrase of them."""
    out = [l for l in block(path, name) if l.startswith("- ")]
    if not out:
        sys.exit(f"{path}: ## {name} has no '- ' bullet lines")
    return "\n".join(out)


def prompt(candidates, taste):
    """Candidates are numbered by position in the caller's stable key order, so the same input
    reproduces the same prompt byte for byte."""
    lines = []
    for i, c in enumerate(candidates, 1):
        abstract = re.sub(r"\s+", " ", c.get("abstract") or "").strip()[:ABSTRACT]
        lines.append(f"[{i}] ({c['source']}) {c['title']}\n{abstract}")
    return PROMPT.format(prefer=section(taste, "Prefer"), reject=section(taste, "Reject"),
                         candidates="\n\n".join(lines))


def call(text, schema, system):
    """ANTHROPIC_API_KEY is dropped here as well as in CI: it takes precedence over the OAuth
    token and silently bypasses the subscription. The timeout is ours rather than a `timeout -k`
    wrapper, so it works off Linux too; a wrapper's exit 124 is still read as a hang below."""
    env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
    try:
        return subprocess.run(
            # --model haiku conserves subscription usage limits, not dollars; --max-turns 4
            # because 1 silently breaks --json-schema, the structured result arriving as a tool
            # call; --tools "" alone still leaves 53 MCP tools, --strict-mcp-config reaches zero.
            ["claude", "-p", "--model", "haiku",
             "--system-prompt", system, "--output-format", "json", "--json-schema", schema,
             "--tools", "", "--strict-mcp-config", "--no-session-persistence", "--max-turns", "4"],
            input=text, capture_output=True, text=True, env=env, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess([], 124, "", "")


def payload(proc, key):
    """The envelope, classified, down to `structured_output[key]`. Never branch on `subtype` — it
    reads "success" on an auth failure. `error_max_turns` lands here as a missing
    structured_output, which is malformed. Shared with pass 2 (claim.py)."""
    if proc.returncode == 124:   # ours above, or a `timeout -k` wrapper: 124, never 143
        raise Retry(f"CLI_HANG: no result in {TIMEOUT}s")
    try:
        env = json.loads(proc.stdout)
        if not isinstance(env, dict):
            raise ValueError("not an object")
    except ValueError as e:
        raise Retry(f"MALFORMED_OUTPUT: envelope is not JSON: {e}") from None
    got = (env.get("structured_output") or {}).get(key)
    if not isinstance(got, list):
        # Only now read the text, and only for the taxonomy. `result` carries the model's own
        # words on a good run, and taste.md says "limit order book" — matching AUTH/LIMITS
        # against a successful envelope would take a working day dark on a quoted `why`.
        result = env.get("result") if isinstance(env.get("result"), str) else ""
        if env.get("api_error_status") == 401 or AUTH.search(result):
            raise Fatal("AUTH_DEAD: regenerate CLAUDE_CODE_OAUTH_TOKEN with `claude setup-token`"
                        f": {result or env.get('api_error_status')}")
        if LIMITS.search(result):
            raise Fatal(f"LIMITS_EXHAUSTED: {result}")   # the reset time is in the text, verbatim
        raise Retry(f"MALFORMED_OUTPUT: no structured_output.{key}: {result[:200]}")
    return got


def parse(proc, ids):
    """Pass 1's entries: one score per candidate id, and the whole id set."""
    got = payload(proc, "scores")
    out = {}
    for s in got:
        if not (isinstance(s, dict) and isinstance(s.get("id"), int)
                and isinstance(s.get("score"), int) and 0 <= s["score"] <= 10):
            raise Retry(f"MALFORMED_OUTPUT: bad entry {s!r}")
        out[s["id"]] = (s["score"], str(s.get("why", "")))
    same_ids(out, ids, "scored")
    return out


def same_ids(out, ids, verb):
    """The schema constrains shape, not completeness: an entry per input id, and no others."""
    if set(out) != ids:
        raise Retry(f"MALFORMED_OUTPUT: id set mismatch, {len(out)} of {len(ids)} {verb}, "
                    f"missing {sorted(ids - set(out))[:5]}, extra {sorted(set(out) - ids)[:5]}")


def run(text, schema, read, label="triage", system=SYSTEM):
    """One run, up to three attempts. A Fatal is not caught: it means the whole day is dark.
    Shared with pass 2 (claim.py), which passes its own parse."""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return read(call(text, schema, system))
        except Retry as e:
            print(f"{label}: attempt {attempt}/{ATTEMPTS}: {e}", file=sys.stderr)
            last = e
    raise Fatal(f"{label} failed after {ATTEMPTS} attempts: {last}")


def triage(candidates, taste, schema):
    """Median of three, and the why from the run that scored the median. Candidates come back in
    publish order — score descending, then key, so a re-run reproduces the tape exactly."""
    ordered = sorted(candidates, key=lambda c: c["key"])
    text = prompt(ordered, taste)
    ids = set(range(1, len(ordered) + 1))
    runs = [run(text, schema, lambda p: parse(p, ids)) for _ in range(RUNS)]
    out = []
    for i, c in enumerate(ordered, 1):
        three = [r[i] for r in runs]
        median = statistics.median(s for s, _ in three)
        out.append(dict(c, score=median, why=next(w for s, w in three if s == median)))
    return sorted(out, key=lambda c: (-c["score"], c["key"]))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--in", dest="src", help="the day's deduped candidates (default stdin)")
    p.add_argument("--out", help="the day's candidates file (default stdout)")
    p.add_argument("--taste", default="taste.md")
    p.add_argument("--schema", default="schema/triage.json")
    a = p.parse_args()
    with (open(a.src) if a.src else sys.stdin) as f:
        candidates = json.load(f)
    if candidates:
        with open(a.schema) as f:
            schema = f.read()
        try:
            candidates = triage(candidates, a.taste, schema)
        except Fatal as e:
            sys.exit(f"triage: {e}")   # dark day: write nothing, commit nothing (§9)
    print(f"triage: {len(candidates)} scored"
          + (f", top {candidates[0]['score']}" if candidates else ""), file=sys.stderr)
    text = json.dumps(candidates, indent=1, ensure_ascii=False) + "\n"
    if not a.out:
        sys.stdout.write(text)
        return
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
