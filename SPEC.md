# SPEC.md

A daily AI-in-finance research tape over two sources, arXiv and SSRN. One static page, six items or
fewer a day, judged by `claude -p` inside GitHub Actions, tuned by a monthly PR against a 45-line
`taste.md`. Vocabulary in [CONTEXT.md](CONTEXT.md).

Every rule below was decided on the [wayfinder map](https://github.com/neoyipeng2018/research-tape/issues/1);
each section links the ticket that holds the evidence. Numbers here are measured, not assumed.

## 0. Shape

```
taste.md                    queries, prefer, reject, bar     (<= 45 lines, hand- or PR-edited)
tape/YYYY-MM-DD.json        published items                  (permanent; also the seen-index)
candidates/YYYY-MM-DD.json  every scanned candidate + score  (pruned at 30 days)
index.html                  today's tape, static             (+ feed.xml over the last 30 days)
scripts/                    fetch, dedup, judge, render, vote-issue, tally-votes, taste-pr, ledger, validate-taste
.github/workflows/          daily.yml, monthly-taste.yml, taste-check.yml, taste-ledger.yml
```

State is those three data paths and nothing else. No database, no Next.js, no hosting beyond GitHub
Pages. No file records that a day failed.

**Repo setting, required before the monthly job ships:** Settings → Actions → General → Workflow
permissions → *Allow GitHub Actions to create and approve pull requests* (off by default; verified
that the PR call 403s without it). The REST field is misleadingly named
`can_approve_pull_request_reviews`.

## 1. Sources

Ticket: [arXiv and Crossref fetch contracts](https://github.com/neoyipeng2018/research-tape/issues/2),
[Whether cs.CE earns an unfiltered lane](https://github.com/neoyipeng2018/research-tape/issues/14).
~38 candidates/day total.

### 1.1 arXiv (~12.8/day at 93% precision)

`GET https://export.arxiv.org/api/query` over HTTPS (`http://` 301s). One call, no paging.

```
search_query = (cat:q-fin.* OR ((cat:cs.CE OR cat:cs.LG OR cat:cs.AI) AND (<TERMS>)))
               AND submittedDate:[<now-7d> TO <now>]
max_results  = 2000
```

`<TERMS>` is the `## Queries` arXiv line of `taste.md`, one shared `abs:`-only term group across all
three `cs.*` lanes:

```
abs:"financial" OR abs:"finance" OR abs:"stock market" OR abs:"portfolio" OR abs:"asset pricing"
OR abs:"credit risk" OR abs:"volatility" OR abs:"algorithmic trading" OR abs:"limit order book"
OR abs:"market microstructure"
```

Rules that are not negotiable without new measurement:

- **Window is a trailing 7 days**, never "yesterday". The search index runs ~3 days behind
  announcements, so a one-day window returns zero on most days and zero on every Monday.
- **`q-fin.*` stays unfiltered** (89% precision alone); the `cs.*` lanes stay filtered. `cs.CE`
  unfiltered is 35% precision — origami metamaterials, integral equations. Filtered it yields
  ~0.86 unique items/day that `q-fin.*` never carries, which is the AI-in-finance intersection this
  desk exists for.
- **Never add bare `abs:"trading"`.** arXiv stems it to *trade* and it matched 196 of 200 false
  positives in the lane. The multiword forms recover the real trading papers.
- **`ti:` adds nothing** — measured zero extra items. The filter stays `abs:`-only.
- **Never use `lastUpdatedDate:[...]` as a filter.** It is byte-identical to `submittedDate` and
  v1-only. The upside: a v2 never reappears in the window, so never-republish is free.

Rate limit: 1 request / 3 seconds, single connection (ToU). Parse Atom XML; take `id` (strip the
`vN` suffix for the key), `title`, `summary` (the abstract — collapse whitespace), the `abs` link.

### 1.2 SSRN via Crossref (~25/day)

```
GET https://api.crossref.org/prefixes/10.2139/works
    ?filter=from-created-date:<now-7d>,until-created-date:<today>
    &rows=1000&cursor=*
    &select=DOI,title,author,abstract,resource,created,type
    &mailto=<contact>
```

- **`from-created-date` is the only usable delta key.** `from-index-date` and `from-deposit-date`
  spike to 185,900 records/day on back-catalogue re-deposits.
- **Window is a trailing 7 days**, matching arXiv, so a missed or degraded run self-heals. This is
  what makes publishing one lane down safe.
- Send `mailto` in both the query string and the User-Agent
  (`research-tape/0.1 (https://github.com/neoyipeng2018/research-tape; mailto:<contact>)`) for the
  polite pool. `rows` above 1000 is a hard 400. Page with `cursor`, never `offset`.
- **Never fetch anything from ssrn.com.** Their terms forbid automated querying, and Crossref already
  carries the full abstract (100/100 records) and the canonical
  `resource.primary.URL` = `https://www.ssrn.com/abstract=<id>`, which is the link we publish.
- **Filter client-side: AI term anywhere AND finance term in title**, both vocabularies read from
  the `ssrn:` line of taste.md (§4), word-boundary matched — `market` as a substring drags in
  `marketing`. `subject` is absent in 100/100 records and `query.bibliographic` is OR-ed relevance
  ranking, not filtering (a garbage term leaves the result set unchanged). Requiring finance in the
  title is what forces the paper to be about finance; letting AI come from the abstract is what
  keeps recall.
- **Unescape until stable, then strip tags,** on both title and abstract. Crossref titles are
  double-escaped (`S&amp;P 500`) and abstracts are JATS-wrapped.

SSRN is the noisy lane — median judge score 2.0 against arXiv's 5. That is expected and costs
nothing; do not go looking for the problem in arXiv.

## 2. Identity and dedup

Ticket: [The identity rule real duplicates break](https://github.com/neoyipeng2018/research-tape/issues/20).

Key = bare arXiv id, or the SSRN DOI. Identity is **exact key, then abstract fingerprint**.
Normalized title is not part of the rule — it is strictly weaker on both real duplicate pairs.

Fingerprint = the set of `[a-z]{4,}` tokens in the lowercased abstract. Two candidates are the same
paper when Jaccard overlap **> 0.35**. Measured: real duplicates score 1.000 and 0.589; the highest
genuine pair scores 0.124; median 0.047.

**Dedup runs once, before judging**, against (a) the day's own candidates and (b) every candidate in
the trailing 30 days of `candidates/*.json` — published or not. The judge scored duplicate pairs
identically 12 times out of 12, so post-judge tie-breaking would never have fired, and cross-day
dedup has to be pre-judge anyway.

Survivor within a cluster: `sort on (source != "arXiv", key)`, keep the first. arXiv wins
cross-source (versioned, permanent id, free PDF, no forbidden landing page); same-source falls to the
lower key, the earlier posting.

```python
def fp(item):
    return set(re.findall(r"[a-z]{4,}", item["abstract"].lower()))

def dedup(candidates, seen):          # seen = prior 30 days of candidates/*.json
    fps = {c["key"]: fp(c) for c in candidates}
    drop = set()
    for a, b in itertools.combinations(candidates, 2):
        ta, tb = fps[a["key"]], fps[b["key"]]
        if len(ta & tb) / len(ta | tb) > 0.35:
            drop.add(max((a, b), key=lambda c: (c["source"] != "arXiv", c["key"]))["key"])
    for c in candidates:
        if any(len(fps[c["key"]] & fp(s)) / len(fps[c["key"]] | fp(s)) > 0.35 for s in seen):
            drop.add(c["key"])
    return [c for c in candidates if c["key"] not in drop]
```

A key present in any `tape/*.json` is dropped outright, at any age. O(n²) is fine at ~38/day against
~1,140 stored records; bucket by rare tokens if volume ever grows.

## 3. Judging

Tickets: [Running claude -p inside GitHub Actions](https://github.com/neoyipeng2018/research-tape/issues/3),
[What a 7 looks like](https://github.com/neoyipeng2018/research-tape/issues/5),
[Whether arXiv ever clears the bar](https://github.com/neoyipeng2018/research-tape/issues/19).

### 3.1 Invocation

```
claude -p --model haiku \
  --system-prompt "You are a research-tape triage classifier. Return only the requested structured output." \
  --output-format json --json-schema "$(cat schema/triage.json)" \
  --tools "" --strict-mcp-config --no-session-persistence --max-turns 4 \
  < prompt.txt > triage.json
```

- Auth is `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`, one-year lifetime — a yearly calendar
  event). **Unset `ANTHROPIC_API_KEY` in CI**: it takes precedence and silently bypasses the
  subscription. `--bare` never reads the OAuth token, so it is unusable here.
- `--system-prompt` cuts fixed overhead 27,712 → 3,398 tokens. `--tools ""` alone leaves 53 MCP
  tools; `--strict-mcp-config` is what reaches zero.
- **`--max-turns 1` silently breaks `--json-schema`** (the structured result arrives as a tool call).
  Use 4.
- **One call for all candidates**, not one per candidate: 60 candidates ≈ 24K tokens, 12% of the
  window, 110s wall clock — of which **89s is time-to-first-token**, which is normal, not a hang.
  Fall back to 2×30 only if retries start failing.
- The schema constrains shape, not completeness. **Compare the returned id set against the input
  set** and treat a mismatch as malformed.
- `--model haiku` conserves subscription usage limits, not dollars. `total_cost_usd` is a client-side
  estimate and `input_tokens` is unreliable (reported `9` on a 25K-token prompt). Do not build cost
  logic on either.

### 3.2 Pass 1 — triage, three runs, median wins

Every deduped candidate is scored 0–10. The identical prompt runs **three times and the median score
wins**; ties break on the stable candidate key so a re-run reproduces the tape exactly.

Median-of-3 does not stabilise the ranking (publish sets overlap 47% either way) and is not meant to:
the residual churn is a genuine five-way tie at 7.0 that the cap cuts through, and votes landing on
interchangeable items do not poison the loop. What it buys is the removal of outlier errors — a
non-finance paper published in 1 of 6 single runs and **0 of 20** median triples.

```
You are the judge for a daily AI-in-finance research tape read by one person: a
quant/ML practitioner who builds LLM systems over financial text and cares whether a
paper changes what they would do next week.

Score EVERY candidate below 0-10 on how much it deserves that person's attention today.

They PREFER:
{taste.md ## Prefer, verbatim}

They REJECT:
{taste.md ## Reject, verbatim}

Anchor the scale:
0-2 off-topic or content-free. 3-4 on-topic but adds nothing. 5-6 solid, competent,
forgettable. 7-8 they would want to know this exists. 9-10 they would stop and read it today.

Be a hard marker. Most papers on most days are 5-6; a 7 is a real recommendation you are
spending their attention on. Judge only from title and abstract; do not credit claims you
cannot see evidence for.

Return one entry per candidate, and nothing else:
{"scores": [{"id": <int>, "score": <int 0-10>, "why": "<max 12 words, the reason for the score>"}]}

CANDIDATES
[{id}] ({source}) {title}
{abstract, whitespace-collapsed, shortened to 900 chars}
```

### 3.3 Pass 2 — the claim, survivors only

```
For each paper below, write the single sentence that goes on a daily research tape
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
{"claims": [{"id": <int>, "sentence": "<the sentence>"}]}

PAPERS
[{id}] ({source}) {title}
{abstract}
```

One entry per paper rather than JSONL: a bare object per line cannot come back through
`--json-schema` (`schema/claim.json`), so pass 2 carries pass 1's envelope shape. The rules are also
re-read on the way out — a sentence that breaks one is malformed and retried, never published.

Without the hard rules, 4 of 6 sentences were semicolon-joined summaries. With them, 12 of 12 came
back clean at 11–18 words.

### 3.4 The bar

**Score ≥ 7, capped at 6 per day.** Bar 8 is measurably worse — publish count swung 2→6 between
identical runs, because a higher line sits deeper in the noise. The distribution at 7 is well spread:
39% ≤4, 39% at 5–6, 23% ≥7.

**One bar, one prompt, one lane list.** No per-source floor and no per-source bar: over five real
days arXiv reached 7 on 18% of candidates against SSRN's 8%, published on all five days, and took 13
of 20 slots.

**Thin days are normal, not an edge case** — two of five days published under the cap. Never publish
filler to fill the page.

## 4. taste.md

Ticket: [What a 7 looks like](https://github.com/neoyipeng2018/research-tape/issues/5).

One file, four sections, **hard cap 45 lines**. The cap is the load-bearing constraint of the whole
design: a full file forces the monthly loop to retire a rule in order to add one, instead of
appending forever.

```markdown
## Queries
arxiv: <the search_query term group, read by the fetcher>
ssrn: ai: <AI terms, comma-separated, matched anywhere>
  finance: <finance terms, matched in the title only>

## Prefer
- <read verbatim into the pass-1 prompt>

## Reject
- <read verbatim into the pass-1 prompt>

## Bar
threshold: 7
cap: 6
```

Parse rules: sections are `## ` headings, order fixed, all four required. `## Prefer` and `## Reject`
are `- ` bullets passed through verbatim. `## Bar` is two `key: int` lines. `## Queries` is two
`name: value` lines — the `ssrn:` one carrying `ai:` then `finance:`, each a comma-separated term
list that may wrap onto indented continuations. Anything else is a parse failure.

`scripts/validate-taste.sh` enforces: all four sections present, ≤ 45 lines, bar parses as integers,
the arXiv query string is syntactically balanced, the `ssrn:` line carries both term lists and
neither is empty, at least one Prefer and one Reject line. The SSRN grammar is checked here and not
only in `fetch-ssrn.py`, so a taste PR that breaks it fails the gate rather than the daily run.
**One script, two call sites** — the first step of the daily run, and a required check on any PR
touching `taste.md`.

The file **ships as seeded, unchanged**, at 41 lines — 30 of taste, plus the 11 the SSRN vocabulary
takes. The cap went 40 → 45 to hold it: the SSRN lists are the dial most likely to be reached for
(that lane runs at 17.1/day against ~25), and a cap with no headroom on it is a cap on the wrong
thing. A sharpened variant was tested and its effect fell inside the noise band, so it was not worth
4 of the 45 lines; the monthly loop can earn them from real votes. Likewise the crypto/CBDC
near-misses in the `cs.CE` lane are deliberately not pre-empted — a real miss showing up in the
thumbs is exactly the evidence the loop wants.

**The 3-vote evidence bar lives in the workflow prompt, never in `taste.md`.** A loop that can edit
its own evidence threshold can lower it.

## 5. The daily page

Ticket: [What the daily page looks like](https://github.com/neoyipeng2018/research-tape/issues/6).
Render target: variant A on `prototype/daily-page`.

One static `index.html`, monospace tape, ~46rem column, no framework and no JS.

- **The claim is the item.** Each row leads with the why-it-matters sentence; the title is a small
  grey link beneath it. The tape is read for what papers *say*, not for a list of names.
- **Source is an inline text prefix, not a badge**: `SSRN — ` ahead of the claim. It disappears on a
  one-source day and reads on a mixed one. Do not group by source — provenance is not the axis anyone
  reads on, and a one-source day then looks like a broken page.
- Two-digit index, hairline rule per row, dense.
- **The frame is four things:** `RESEARCH TAPE` + the date on a rule; one grey meta line
  (`N of M scanned · arXiv + SSRN`); `archive`; `rss`.
- **A thin day is acknowledged in words** under the last row: *"Nothing else cleared the bar today."*
  It stays on a zero-item day. The count alone reads as a page that failed to load.
- The date line always states the date of the tape being shown. Staleness is left for the reader to
  notice — no banner, no client-side threshold.

The renderer reads one tape file and writes both outputs; `scripts/render.py --tape-dir tape --out .`,
with `scripts/fixtures/` as the shape it is checked against:

```json
{"date": "2026-08-19", "scanned": 31,
 "items": [{"key": "...", "title": "...", "link": "...", "source": "arXiv", "claim": "..."}]}
```

`scanned` is the day's candidate count after dedup — the M in the meta line. A tape missing a field
renders nothing and exits non-zero (§9); it never guesses.

`feed.xml` is a plain RSS 2.0 file rebuilt from the last 30 `tape/*.json`, one `<item>` per published
item: title, link, claim as description, tape date as `pubDate`, key as `guid`.

Dated HTML permalink pages are out of scope for now (map fog).

## 6. Votes

Ticket: [GitHub-native votes and bot-raised PRs](https://github.com/neoyipeng2018/research-tape/issues/4).

Every day the loop runs — including quiet days — it opens one issue holding that day's items as a
checklist. **Two boxes per item**, not one, because the loop needs three states: liked, disliked,
didn't look. Never pre-tick: a pre-ticked "keep" manufactures approval for everything ignored.

```markdown
### [Correlated AI forecasts increase systemic risk…](https://arxiv.org/abs/2608.01234)
- [ ] 👍 more like this <!--v:up:arxiv:2608.01234-->
- [ ] 👎 less like this <!--v:down:arxiv:2608.01234-->
```

Generator rules:

1. The key rides a **trailing** HTML comment on the checkbox line. A leading comment destroys the
   checkbox entirely.
2. Emit only the documented form `- [ ]`, with the space after `]`. `- [ ]no space` renders no
   checkbox at all.
3. **No `#123`, no github.com issue or PR URL, anywhere on a vote line.** A task-list line that
   references an issue auto-ticks when that issue closes — a fabricated vote. Paper links live in the
   heading, which is not a task list.
4. The parser stays liberal: accept `-`/`*`/`+` and both `x`/`X`.
5. Read votes with one `GET /repos/{owner}/{repo}/issues/{n}` → `.body`. Bodies round-trip
   byte-identical.
6. Find issues with `GET /issues?labels=vote` (1,000/hr), never `/search/issues` (30/min).

**A ticked box carries no timestamp** — body edits produce zero timeline and zero issue events, and
`userContentEdits.diff` is a nullable, undocumented summary that must not be built on. So there is no
consumed-marker at all: the monthly job reads a **rolling 30-day window** of vote issues. Late ticks
land inside the window, reruns are idempotent, and it matches the `candidates/*.json` retention.
Accepted cost: a tick on an issue older than 30 days is never counted.

The vote issue is also the **status surface** — degraded lanes, quiet days, the no-PR-this-month line
and the stale-PR line are appended to it. And it is the **heartbeat**: its arrival every morning is
the proof the loop is alive, and its absence is the only signal that catches a cron that silently
stopped firing.

## 7. The monthly taste PR

Ticket: [What the weekly taste PR looks like](https://github.com/neoyipeng2018/research-tape/issues/7).
Rendered mock: [PR #18](https://github.com/neoyipeng2018/research-tape/pull/18).

**Monthly**, reading the same rolling 30-day window, so cadence and window match and consecutive runs
never re-read the same votes. (Weekly would need suppression rules — "already proposed", "already in
`taste.md`" — purely to stop the same evidence nagging four runs deep. Matching the two deletes both
rules.)

It edits `taste.md` and nothing else, **at most 3 line changes**, each citing the specific thumbed
items behind it.

Body, in order:

1. **Header line** — change count, total votes with the 👍/👎 split, window dates, `taste.md` line
   count before → after.
2. **The ledger** — one **pre-ticked** checkbox per proposed change, each showing the resulting
   `taste.md` line in italics. Untick to drop: a `pull_request: edited` workflow diffs the ledger,
   rewrites `taste.md`, force-pushes and comments what it dropped. Merge takes what is still ticked;
   close takes nothing. Ledger lines carry rule text only — same no-cross-reference hazard as §6
   rule 3.
3. **Tally table** — window dates, items published, thin and empty days, votes and how many days
   carried them.
4. **A section per change** — the change as a fenced ` ```diff ` block, one paragraph arguing why the
   votes say this, an evidence table, then the replay line. Each evidence row is
   👍/👎 · **paper title linked to arXiv or SSRN** · **the vote day linked to that day's vote issue**.
   Both links: the paper is what gets clicked, the vote issue is what makes the claim checkable.
5. **Seen, not proposed** — signals that missed the evidence bar, and votes that were not about taste.
   This is what stops the loop looking like it ignored you.

**Replay is demotion-only**, scoped to the month's published items — one extra judge pass over ~140
items rather than the whole candidate pool. Votes only exist on published items, so a replay can show
what a rule would demote and never what it would admit; a dropped Reject line replays as "nothing
changes" and shows its effect on next month's tape.

**No PR is raised when:** no proposed line has **≥3 votes pointing the same way** in the window; or
the bar is clear but nothing is worth proposing; or a taste PR is already open.

**When nothing is proposed, say so** — one line appended to that day's vote issue:

> *No taste change this month — 6 votes in the window, nothing reached the 3-vote bar.*

Silence makes "the loop is thinking" and "the loop is broken" look identical.

**There is only ever one open taste PR.** The next month force-pushes the same branch, rewrites the
body, and comments what it retired and why. The **3-change budget is per open PR, not per month**, so
a new month's change has to beat one already on the table. Retiring a change can move the line count,
since a dropped line may be paying for an added one.

## 8. Workflows

Daily, ~06:00 SGT:

```yaml
name: Research Tape Daily
on:
  schedule: [{ cron: "0 22 * * *" }]
  workflow_dispatch:
permissions:
  contents: write
  issues: write
concurrency: { group: research-tape-daily, cancel-in-progress: false }
env:
  CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
  DISABLE_AUTOUPDATER: "1"
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"
jobs:
  tape:
    runs-on: ubuntu-latest
    timeout-minutes: 30
```

Steps, in order: validate `taste.md` → install `@anthropic-ai/claude-code` → **probe auth**
(`claude -p "Reply with the single word ok" --model haiku`, `timeout -k 10 120`) → fetch both lanes →
dedup → triage ×3 (`timeout -k 30 600` per call, `timeout-minutes: 15` on the step) → claims → write
`tape/` + `candidates/` → prune `candidates/*.json` older than 30 days → render `index.html` and
`feed.xml` → commit and push → open the vote issue.

A green run lands in ~12 minutes, measured: ~9m30 of that is triage's three judge calls, run in
sequence at ~190s each over ~100 candidates, and ~1m40 is the claim call. Nothing waits on this —
Actions minutes are free on a public repo, the cron fires 22:00 UTC and the reader opens the page
at 06:00 SGT, and `cancel-in-progress: false` on a daily job means a slow run collides with
nothing. The binding limits are the ones above: 600s per judge call, 15 minutes on the triage
step, 30 minutes on the job. The three triage calls are independent and could run concurrently
for ~6 minutes total, but that trades away the call-count assertions the failure taxonomy in §9
is tested through — worth doing only if candidate volume starts to threaten the 15-minute step.

Monthly (`monthly-taste.yml`): `contents: write`, `issues: write`, `pull-requests: write` — all three;
`pull-requests: write` only covers `POST /pulls`, the branch still has to be pushed. Issues are
`write` and not `read` because the no-change line of §7 is a comment the job posts; the reading
half alone would be `read`.

Also: `taste-check.yml` (the validator as a required check on PRs touching `taste.md`) and
`taste-ledger.yml` (`on: pull_request: [edited]`, the untick handler from §7).

Two consequences of the default `GITHUB_TOKEN`: the daily push **will not trigger any `push`
workflow**, so any rebuild step must live in the same job; and there is no `workflows` permission
scope at all, so the loop can never edit its own workflows — a free safety property.

`workflow_dispatch` is the entire retry mechanism.

## 9. Failure

Ticket: [What happens when the loop breaks](https://github.com/neoyipeng2018/research-tape/issues/8).

Two channels, both of which already exist: GitHub's failed-workflow email is the alarm, the daily vote
issue is the heartbeat. Nothing else is built — no sentinel workflow, no badge, no webhook.

**Default response, so the table lists only exceptions:** any error the run cannot reason about →
exit non-zero, write nothing, commit nothing. The site keeps yesterday's tape. Tomorrow retries from
scratch with no memory of the failure — no in-run retries, no partial commits, no failure state file.
Safe because identity already prevents republishing and both windows are trailing, so a missed day
costs at most a few items that come back tomorrow.

| Failure | Behaviour | Notification |
|---|---|---|
| arXiv lane unreachable or garbage | Publish from Crossref alone. Published, not dark | One line on the vote issue. Run green |
| Crossref lane unreachable or garbage | Publish from arXiv alone; the 7-day window returns the skipped DOIs tomorrow | One line on the vote issue. Run green |
| Both lanes down | Dark day, default response | Failure email, no vote issue |
| Judge auth dead | Dark day. **Not distinguished from limit exhaustion in code** | Failure email; `api_error_status` says which. Fix the secret, then `workflow_dispatch` |
| Judge limits exhausted | Dark day. No in-run sleep or retry | Failure email. `workflow_dispatch` once limits reset |
| Zero candidates clear the bar | **Quiet day.** Commit an empty `tape/YYYY-MM-DD.json`; the page says nothing cleared | Vote issue opens with no checkboxes and a zero-cleared line. Run green |
| Cross-source duplicate | Prevented by §2, never detected here | None. It never publishes |
| `taste.md` unparseable | Validator runs first, before any fetch. Dark day. **No fallback to the last good version** | Failure email. Usually caught earlier by the same validator on the PR |
| Taste PR sitting unmerged | Nothing breaks; next month force-pushes it, votes age out on their own | One line on the vote issue on force-push day, naming the PR and how long it has sat |
| Schedule silently not firing | Nothing happens, so no email | No vote issue that morning; the page's date stops moving |
| Schedule auto-disabled (60 days idle) | Permanent stop; manual re-enable | Sustained absence of vote issues. Accepted, not defended against |

Failure taxonomy inside the judge step, branching on the JSON envelope — **never on `subtype`**, which
still reads `"success"` on an auth failure:

| | Detection | Response |
|---|---|---|
| AUTH_DEAD | `api_error_status: 401`, or result text matching authenticate/expired/OAuth | Never retry; regenerate the token |
| LIMITS_EXHAUSTED | limit/resets/balance in `result` (429 implied but untriggerable on demand) | Never retry; fail with the reset time |
| CLI_HANG | `timeout` exits **124**, not 143 | Retry ×3 |
| MALFORMED_OUTPUT | Valid envelope, missing/short `structured_output`, or an id-set mismatch; includes `error_max_turns` | Retry ×3 |

A bogus OAuth token fails in 2.4s; a bogus API key takes 180s because the CLI retries the 401
internally — which is why the probe needs its own timeout.

**Deliberately rejected:** a sentinel workflow, burn-rate projection, a freeze file, a kill switch,
falling back to the last good `taste.md` (git already holds it, and silently judging against taste
you did not write is worse than a dark day), sleeping inside a run on limit exhaustion, a separate
liveness check (it can stop firing too), a heartbeat commit to dodge the 60-day cliff, and
client-side staleness detection.

## 10. Out of scope

Anonymous reader voting and any analytics backend. Any source beyond arXiv and SSRN. Numeric weight
learning in every form — bounded dials, Beta posteriors, evidence gates, freeze files,
rank-instability guards — replaced wholesale by a human reading a prose diff in a PR. OpenAlex, which
has nothing left to enrich once Crossref supplies title, authors, full abstract and canonical URL.
