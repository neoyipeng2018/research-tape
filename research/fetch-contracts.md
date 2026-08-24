# arXiv and Crossref fetch contracts

Research for [issue #2](https://github.com/neoyipeng2018/research-tape/issues/2). Every number below
came from a live call made on **2026-08-24, 14:36–15:20 UTC**. Queries are copy-pasteable.

Primary sources: [arXiv API User's Manual](https://info.arxiv.org/help/api/user-manual.html),
[arXiv API Terms of Use](https://info.arxiv.org/help/api/tou.html),
[Crossref REST API docs](https://api.crossref.org/swagger-ui/index.html),
plus the live endpoints themselves.

---

## TL;DR for the spec

| | |
|---|---|
| arXiv endpoint | `https://export.arxiv.org/api/query` (**HTTPS** — `http://` returns 301) |
| arXiv delta key | `submittedDate:[YYYYMMDDHHMM+TO+YYYYMMDDHHMM]`, **trailing 7-day window**, deduped against the seen-index |
| arXiv volume | **12.8 candidates/day** at 93% precision with the recommended query |
| arXiv rate limit | 1 request / 3 seconds, single connection |
| Crossref endpoint | `https://api.crossref.org/prefixes/10.2139/works` |
| Crossref delta key | **`from-created-date`** — the other two are unusable, see §2.1 |
| Crossref raw volume | ~900–1,500 new SSRN DOIs/day, **not finance-only** |
| Crossref filtered volume | **~25/day** with `AI-anywhere AND finance-in-title` |
| Crossref rate limit | 10 req/s, concurrency 3 (polite pool); 5 req/s, concurrency 1 (anonymous) |
| OpenAlex | **OUT on day one.** See §3 |
| Total judge load | **~38 candidates/day** |

Two findings overturn the assumptions written on the map, both in §1.2 and §1.4. Read those first.

---

## 1. arXiv

### 1.1 Category grammar — the wildcard is real

`cat:q-fin.*` is not a convenience; it resolves to exactly the deduped union of the nine
subcategories. Verified by counting each subcategory and comparing:

```
cat:q-fin.CP  3321      cat:q-fin.PR  2258      cat:q-fin.ST  4334
cat:q-fin.EC     0      cat:q-fin.PM  2441      cat:q-fin.TR  2332
cat:q-fin.GN  3064      cat:q-fin.RM  3036      cat:q-fin.MF  3383
                                        sum of subcategories = 24169
cat:q-fin.*  = 18860
cat:q-fin*   = 18860
explicit "cat:q-fin.CP OR cat:q-fin.EC OR ..." = 18860   <- identical
```

The wildcard equals the explicit OR exactly. The sum (24,169) is higher only because cross-listed
papers get counted once per subcategory. **Use `cat:q-fin.*`** — one token instead of nine.

> `q-fin.EC` returns **0** results. It was aliased to `econ.GN` years ago. Listing it costs nothing
> but buys nothing; the wildcard covers it either way.

Boolean grammar that works, URL-encoded: `+AND+`, `+OR+`, `+ANDNOT+`, parentheses as `%28`/`%29`,
phrases as `abs:%22asset+pricing%22`. Fields: `ti:`, `abs:`, `au:`, `cat:`, `all:`.

### 1.2 FINDING: `abs:` stems, and `abs:"trading"` poisons the whole lane

The naive term list on the map produced a top hit of *"CLEAR: Continuous Latent Adapter Routing for
Utility-Preserving LLM Safety Alignment"* — an LLM safety paper with nothing to do with finance.

Its abstract contains **"trade-off"** and does **not** contain the string "trading" anywhere. arXiv
stemmed `trading` → `trade` and matched. Per-term precision over 2026-08-01..21 in the cs.LG/cs.AI
lane, scoring each hit on whether a real finance token appears in title or abstract:

```
term              hits  clean  junk  precision
financial           88     88     0       100%
finance             37     37     0       100%
stock market         4      4     0       100%
trading            253     57   196        23%   <-- the polluter
portfolio           22     22     0       100%
asset pricing        1      1     0       100%
credit risk          3      3     0       100%
volatility          27     23     4        85%
```

One term supplies 196 of the 200 false positives. Every other term is 85–100% clean. **Drop bare
`abs:"trading"`**; the multiword forms `algorithmic trading`, `limit order book`,
`market microstructure` recover the genuine trading papers without the stem collision.

### 1.3 FINDING: `cs.CE` unfiltered is 65% noise

The map specifies `cs.CE` unfiltered. cs.CE is *"Computational Engineering, Finance, **and
Science**"* — the finance part is a third of its charter. Measured over 21 days:

```
cs.CE unfiltered        total=145  clean= 51  junk= 94  precision= 35%   6.9/day
cs.CE + finance terms   total= 20  clean= 20  junk=  0  precision=100%   1.0/day
```

Unfiltered cs.CE contributes 61 of the union's 113 junk items — origami metamaterials,
Calderón-preconditioned integral equations, an infarct-growth reaction-diffusion model. Applying the
same finance terms already used for cs.LG/cs.AI takes it to 100% precision.

### 1.4 Recommended query

Term-filter `cs.CE` alongside `cs.LG`/`cs.AI`; leave `q-fin.*` unfiltered (89% precision on its own —
it is a finance archive by definition).

```
%28cat:q-fin.*+OR+%28%28cat:cs.CE+OR+cat:cs.LG+OR+cat:cs.AI%29+AND+%28abs:%22financial%22+OR+abs:%22finance%22+OR+abs:%22stock+market%22+OR+abs:%22portfolio%22+OR+abs:%22asset+pricing%22+OR+abs:%22credit+risk%22+OR+abs:%22volatility%22+OR+abs:%22algorithmic+trading%22+OR+abs:%22limit+order+book%22+OR+abs:%22market+microstructure%22%29%29%29
```

Measured against the map's naive version, same 21-day window:

| query | per day | precision |
|---|---|---|
| map's version (`cs.CE` open, bare `trading`) | 25.6 | 50% |
| recommended | **12.8** | **93%** |

Half the candidates, and the half that survives is the right half.

### 1.5 FINDING: "new since yesterday" does not exist — the index runs ~3 days behind

Per-day counts by `submittedDate` window, run at 2026-08-24T14:36Z:

```
date         dow   q-fin  cs.CE  LG/AI  UNION
2026-08-24  Mon       0      0      0      0     <- today
2026-08-23  Sun       0      0      0      0     <- "yesterday"
2026-08-22  Sat       0      0      0      0
2026-08-21  Fri       2      5     10     16     <- newest data
2026-08-20  Thu       4      4     17     25
2026-08-19  Wed       3     12     20     31
...
2026-08-07  Fri       5      9     17     29
```

This is not a q-fin quirk. The newest indexed submission **anywhere on arXiv** was the same:

```
cat:cs.LG      sortBy=submittedDate desc -> 2608.21359v1  published=2026-08-21T17:59:37Z
cat:math.*     sortBy=submittedDate desc -> 2608.21359v1  published=2026-08-21T17:59:37Z
cat:astro-ph.* sortBy=submittedDate desc -> 2608.21353v1  published=2026-08-21T17:57:04Z
```

Every category stops dead at **2026-08-21T17:59:37Z**, ~71 hours before the query. The sharp cutoff
at 17:59 UTC is 13:59 EDT — arXiv's 14:00 ET submission deadline. Papers submitted after Friday's
deadline are announced Monday, and the search index moves with announcements, not submissions.

**Consequence for the fetcher: a cron job asking for "yesterday" returns zero on most days and zero
on every Monday.** Query a **trailing 7-day window** and let the seen-index do the deduplication.
That is ~90 rows per run of which ~13 are new — one API call, and it self-heals if a run is missed.

### 1.6 FINDING: `lastUpdatedDate:[...]` is a trap — both range filters are v1-only

The ticket asks whether to express freshness as a `submittedDate` range or as
`sortBy=lastUpdatedDate`. These are **not two routes to the same place**.

`sortBy=lastUpdatedDate&sortOrder=descending` with no date filter surfaces revisions:

```
2608.20842v1  published=2026-08-21T08:05:04Z  updated=2026-08-21T08:05:04Z
2608.07479v2  published=2026-06-03T13:14:14Z  updated=2026-08-21T00:07:35Z  <- REVISION
2208.06046v6  published=2022-08-11T21:33:57Z  updated=2026-08-20T19:57:29Z  <- REVISION
2504.15985v2  published=2025-04-22T15:38:31Z  updated=2026-08-20T16:49:47Z  <- REVISION
2508.00554v5  published=2025-08-01T11:48:13Z  updated=2026-08-20T09:06:07Z  <- REVISION
```

But the *range filter* of the same name does not. Both fields, identical window, identical result:

```
submittedDate:[202608200000+TO+202608212359]   -> 6 ids, all v1
lastUpdatedDate:[202608200000+TO+202608212359] -> 6 ids, all v1   (byte-identical set)
known revisions present in either: NONE
```

`2208.06046v6` was updated on 2026-08-20 and is absent from a `lastUpdatedDate` range covering
2026-08-20. **Both range filters match on the v1 submission date regardless of which name you use.**
Only the `sortBy` reads the revision timestamp.

This is convenient rather than annoying: it means the map's *"a published key never republishes"*
rule is enforced by the API for free.

### 1.7 How a v2 presents

Fetched by bare id (no version suffix), arXiv returns the **latest** version:

```
id_list=2608.07479 -> <id>http://arxiv.org/abs/2608.07479v2</id>
                      published=2026-06-03T13:14:14Z   (v1 submission)
                      updated  =2026-08-21T00:07:35Z   (v2 revision)
```

- `<id>` carries the version suffix; `published` is always v1; `updated` is the current version.
- **A v2 does not reappear in a `submittedDate` window** (§1.6). Deduping on the bare id
  (`2608.07479`, suffix stripped) is therefore belt-and-braces, but do it anyway — it costs one
  `rsplit("v", 1)` and protects against arXiv changing this.

### 1.8 Rate limits and pagination — verbatim from primary sources

Terms of Use:

> When using the legacy APIs (including OAI-PMH, RSS, and the arXiv API), make no more than **one
> request every three seconds**, and limit requests to a **single connection** at a time.

User's Manual:

> the maximum number of results returned from a single call (`max_results`) is limited to **30000**
> in slices of at most **2000** at a time, using the `max_results` and `start` query parameters

> In cases where the API needs to be called multiple times in a row, we encourage you to play nice
> and incorporate a **3 second delay** in your code.

The recommended query over 7 days returns ~90 results — **one call, no paging, no sleep needed**.
Response is Atom XML; `<opensearch:totalResults>` gives the count. Verified `max_results=2000`
returns all 179 entries of a wider query in a single response.

### 1.9 Fields available per entry

```
id            http://arxiv.org/abs/2608.21278v1
published     2026-08-21T16:36:10Z
updated       2026-08-21T16:36:10Z
title         CLEAR: Continuous Latent Adapter Routing for ...
authors       ['Chengxiao Wang', 'Enyi Jiang', 'Xiaojing Liao', 'Sanmi Koyejo']
primary_cat   cs.AI                       (<arxiv:primary_category term="...">)
all cats      ['cs.AI']                   (<category term="...">, repeated)
abs link      https://arxiv.org/abs/2608.21278v1
summary       full abstract, newline-wrapped — collapse whitespace before use
```

All four fields the map's item model needs (title, link, source badge, why-it-matters input) come
from one call. `summary` is the judge's input.

---

## 2. Crossref

### 2.1 FINDING: `from-created-date` is the only usable delta key

The ticket asks which of the three date filters is reliable. Per-day counts for prefix `10.2139`:

```
date         dow   index   created  deposit
2026-08-24  Mon      774     544     662
2026-08-23  Sun     1591      65     221
2026-08-22  Sat      748     522     634
2026-08-21  Fri     1654     907    1061
2026-08-20  Thu     1809    1117    1260
2026-08-19  Wed     2295    1514    1657
2026-08-18  Tue     4225    1353    1516
2026-08-17  Mon     1195     981    1122
2026-08-16  Sun    21356     631   21372   <-- spike
2026-08-15  Sat     1441    1285    1341
2026-08-14  Fri   185900     700  186684   <-- spike
2026-08-13  Thu    92483    1033   92781   <-- spike
2026-08-12  Wed    95834    1434   96217   <-- spike
2026-08-11  Tue   101541     987  101992   <-- spike

14-day totals: index=512,846   created=13,073   deposit=508,520
```

`from-index-date` and `from-deposit-date` move together and spike to **185,900 records in one day** —
39× the entire 14-day created total. Sampling that spike shows what it is:

```
DOI 10.2139/ssrn.3914025 | issued 2021 | created 2021-08-31 | deposited 2026-08-13
DOI 10.2139/ssrn.3422152 | issued 2019 | created 2021-11-17 | deposited 2021-11-17
DOI 10.2139/ssrn.7228048 | issued 2026 | created 2026-08-14 | deposited 2026-08-14
```

A 2021 paper, first created in 2021, **re-deposited in 2026**. The spikes are SSRN/Elsevier bulk
re-depositing its back catalogue. `deposited` is mutable — it moves every time the publisher touches
a record — and `indexed` follows it. Either one as a delta key would pull ~186,000 mostly-decade-old
records on a bad day.

`created` is the immutable timestamp of first DOI registration and is flat at 544–1,514/day.
**Use `from-created-date` + `until-created-date`.** Unlike arXiv there is **no lag**: 2026-08-24 had
544 records by 14:36 UTC the same day.

### 2.2 FINDING: SSRN via Crossref is not a finance feed

The map treats `10.2139/ssrn` as an SSRN-shaped, finance-shaped stream. It is not. Real titles from
the 2026-08-21 delta:

```
- MEELF: Morphology Evidence and Expert Learning Framework for Sperm Classification
- Social Connections and Sex Modify Associations Between Systemic Inflammation and Gait Decline
- RBL-YOLO: ... Object Detection for Nighttime Low-Light Environments
- Machine Learning-Based Tribological Parameters Prediction for Al7068/(SiC + Fly Ash) Composites
- Separation of Powers and the Rule of Law
- Outside Options and Labor Supply: Evidence from the Gig Economy
```

SSRN is now Elsevier's general-purpose preprint server. The ~900–1,500 new DOIs/day span medicine,
materials science, law and CS. **`subject` is absent in 100/100 sampled records**, so there is no
metadata field to filter on — filtering must be done client-side on title + abstract text.

### 2.3 `query.bibliographic` cannot do the filtering

Tempting, but it is OR-ed relevance ranking, not filtering. Proof:

```
query.bibliographic=machine+learning   -> 42,626
query.bibliographic=machine            -> 15,907
query.bibliographic=learning           -> 40,718
query.bibliographic=zzzqqq+learning    -> 40,718   <- garbage term changes nothing
```

A term that matches no document leaves the result set byte-identical to the other term alone. Any
`query.*` param would return the whole corpus relevance-sorted. **Pull the day's delta and filter
locally.** It is one call and ~5 seconds anyway.

### 2.4 Prefilter options, measured

Applied to the 2026-08-19 delta (1,514 records), AI-term and finance-term regexes over title/abstract:

```
AI in title AND FIN in title       11    tight; misses papers whose finance framing is in the abstract
AI in title AND FIN anywhere       73    noisy — "financial" in a funding statement counts
AI anywhere AND FIN in title       25    <- recommended
AI anywhere AND FIN anywhere      122    too loose (metal-organic frameworks, lithium-ion batteries)
```

**Recommend `AI anywhere AND FIN in title` ≈ 25/day.** Requiring the finance token in the *title*
forces the paper to actually be about finance, while letting the AI signal come from the abstract.
Titles that survive the strictest variant show the target is real:

```
- Agentic Artificial Intelligence and Systemic Financial Risk: A Complex-Systems Framework
- Chips as Collateral: Vendor-Supported Chip-Backed Debt and the Financing of the AI Buildout
- Explainable Artificial Intelligence for Dynamic Credit Risk Assessment: X-DyAR
- Accurate but Correlated: Common AI Forecast Errors and Endogenous Market Volatility
- The Effects of Artificial Intelligence Engagement on Socially Responsible Banking
```

### 2.5 Polite pool — measured, not quoted

Response headers, read case-insensitively:

```
mailto= param + UA    pool=polite-single  limit=10/1s  concurrency=3
mailto in UA only     pool=polite-single  limit=10/1s  concurrency=3
no mailto anywhere    pool=public-single  limit= 5/1s  concurrency=1
```

Polite pool buys **2× the request rate and 3× the concurrency**, and a contact address if a query
misbehaves. `mailto` in *either* the query string or the User-Agent is sufficient — both reached
`polite-single`. Use both:

```
User-Agent: research-tape/0.1 (https://github.com/neoyipeng2018/research-tape; mailto:...)
```

The daily job makes 1–2 calls, so the rate ceiling is irrelevant; do it because it is free and it is
the documented courtesy.

### 2.6 Paging and payload

- `rows` max is **1000**. `rows=1001` → **HTTP 400**.
- Deep paging uses `cursor=*`, then `next-cursor` from each response. `offset` is capped at 10,000
  and is not needed here.
- One full day (1,514 records) took **2 calls and 7.2 seconds**.
- `select` trims the payload hard: 50 rows went from **286,962 → 7,313 bytes** (39×) with
  `select=DOI,title`. Abstracts dominate the response size, so select only what is needed.

### 2.7 Fields actually present (n=100 from one created-date day)

```
title            100/100
author           100/100
abstract         100/100    <- JATS-wrapped: <jats:p>...</jats:p>, strip tags
URL              100/100    https://doi.org/10.2139/ssrn.7314699
resource         100/100    resource.primary.URL = https://www.ssrn.com/abstract=7314699
issued           100/100    year-only: [[2026]]
type             100/100    "posted-content"
license          100/100
reference         50/100
container-title    0/100
subject            0/100    <- no topic metadata, hence §2.2
```

Also present: `group-title: "SSRN"`, `publisher: "Elsevier BV"`, `posted: [[2026]]`.

Two things matter here:

1. **`resource.primary.URL` is the canonical SSRN abstract page** — `https://www.ssrn.com/abstract=<id>`.
   This is the link the map wants, and it arrives inside the Crossref response. **Nothing needs to be
   fetched from SSRN**, which keeps the carried constraint intact.
2. **Abstracts arrive in full, 100% of the time.** The judge needs no second source.

Watch for HTML-escaped markup leaking into titles — real example:
`&lt;p&gt;&lt;span&gt;The Concept of Locus Standi...`. Unescape entities, then strip tags, on both
title and abstract.

### 2.8 Working query

```
https://api.crossref.org/prefixes/10.2139/works
  ?filter=from-created-date:2026-08-23,until-created-date:2026-08-23
  &rows=1000
  &cursor=*
  &select=DOI,title,author,abstract,resource,created,type
  &mailto=<contact>
```

Observed: `total-results: 65` for 2026-08-23 (a Sunday), 907 for Friday 2026-08-21.

Use a **2-day** window (`today-1` .. `today`) rather than a single day, so a late-running or missed
job does not drop a day. The seen-index dedupes the overlap.

---

## 3. OpenAlex — recommend OUT

**Out on day one.** Not a close call.

The carried findings said OpenAlex lags Crossref and cannot supply freshness. A confirming probe on
two SSRN DOIs Crossref already held:

```
10.2139/ssrn.7315494 -> FOUND, publication_date 2026-01-01
10.2139/ssrn.7304279 -> FOUND, publication_date 2026-01-01
```

Both resolve, and both carry the January-1 normalization — the exact failure already documented. But
the stronger argument is that the enrichment has nothing left to enrich. Crossref already delivers
title, authors, full abstract, and the canonical SSRN URL for 100% of records (§2.7). OpenAlex would
add topic concepts and citation counts — and a day-old preprint has zero citations by construction.

Cost of including it: one HTTP call per candidate, ~25 calls/day, plus a failure mode (a 404 on a
fresh DOI) for metadata the pipeline does not need. **Skip it.** Revisit only if the
"did-it-matter-later" signal on the map gets built, where citation counts are the actual payload.

---

## 4. Expected daily volume

| source | raw | after filtering | notes |
|---|---|---|---|
| arXiv | ~90 per 7-day window | **12.8/day** @ 93% precision | 1 call, no paging |
| Crossref/SSRN | 900–1,500/day | **~25/day** | 1–2 calls, client-side filter |
| **total into pass-1 judge** | | **~38/day** | |

Against a publish bar of score ≥ 7 capped at 6/day, ~38 candidates is a healthy funnel — enough that
the cap binds on strong days without the judge burning tokens on 1,500 medical preprints.

Two numbers to sanity-check once running: arXiv Mondays will carry a weekend backlog (Friday
post-deadline + Saturday + Sunday announce together), and Crossref weekend days run light (65 records
on Sunday 2026-08-23 vs 1,514 on Wednesday).

---

## 5. Gotchas a build session would otherwise hit

1. `http://export.arxiv.org` returns **301** — use HTTPS or follow redirects.
2. arXiv's index is **~3 days behind**; "yesterday" returns 0. Use a trailing 7-day window (§1.5).
3. `lastUpdatedDate:[...]` as a *range filter* silently behaves as `submittedDate` (§1.6).
4. `abs:` **stems** — `abs:"trading"` matches "trade-off" and is 77% junk (§1.2).
5. `cs.CE` includes Science and Engineering, not just Finance — filter it (§1.3).
6. Crossref `from-deposit-date` / `from-index-date` spike to 185,900/day on bulk re-deposits (§2.1).
7. Crossref `query.*` params are OR-ed relevance, never filters (§2.3).
8. `rows` max 1000; 1001 is a hard 400 (§2.6).
9. SSRN abstracts are JATS-wrapped and titles can carry escaped HTML (§2.7).
10. Crossref rate-limit headers are lowercase — read them case-insensitively or you will conclude,
    wrongly, that the polite pool did nothing.
