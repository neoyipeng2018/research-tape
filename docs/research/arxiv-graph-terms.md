# Do graph terms earn a place in the arXiv lane?

Ticket: [#46](https://github.com/neoyipeng2018/research-tape/issues/46). Measured 2026-09-19.

**Answer: no. Add nothing.** Across 90 days, `abs:"graph neural network" OR abs:"knowledge graph"`
adds 583 papers. One of them is weakly on-theme and 581 are false positives (99.7%). None of the
other candidate terms clears the bar SSRN set. `taste.md` is unchanged, so the change costs 0 lines.

## Method

Source: the arXiv API (`https://export.arxiv.org/api/query`), using the probe from #46 unchanged
apart from three things. `now` is fixed at 2026-09-19 12:00 UTC. The script reads
`scripts/fetch-arxiv.py` and `taste.md` from a checkout identical to `main@cee4234`. Files and cache
go in a scratch directory. The probe waits at least 3.5 s between requests, caches every response
and backs off when throttled. The run had no retries and no throttling.

Each term was run as:

```
((cat:cs.CE OR cat:cs.LG OR cat:cs.AI) AND abs:<term>) ANDNOT (<taste.md arxiv line>)
  AND submittedDate:[now-Nd TO now]
```

cs.SI was run as `(cat:cs.SI AND (<today's abs group>)) ANDNOT (<taste.md arxiv line>)`.

- The baseline (today's query, 7 days) returned 55 items.
- Three 90-day counts (KG 300, GNN 295, market 200) looked suspiciously round. I checked each
  against the API's `opensearch:totalResults`, and all three matched, so no results were cut off.
- The 7-day window really covers only about 4 days, because the search index lags about 3 days
  (SPEC §1.1).

Every paper was classified by hand from its title and abstract. I read every title; I read the full
abstract whenever the title or abstract contained a finance word (stock, equity, asset, invest*,
trad*, price, bank, credit, loan, fraud, firm, econom*, crypto, blockchain, transaction, market,
returns and similar). No term went over 300 results, so there was no sampling.

- **On-theme** means AI-in-finance and about network structure as signal.
- **Off-theme** means AI-in-finance, or finance, but not about graphs.
- **FP** means not finance.

## Stemming: two pairs return identical sets

arXiv stems these phrases, so each pair below returns exactly the same papers in both windows:

- `"stock"` and `"stocks"`
- `"equity"` and `"equities"`

`"stock"` matches the inventory sense (base-stock policies, carbon and biomass stock, "the
observable stock" of a registry). `"equity"` matches the fairness sense (health equity, DEI).

## Per-term results

Each cell reads extras / on-theme / off-theme / FP.

| Term | 7 days | 90 days |
|---|---|---|
| `"graph neural network"` | 13 / 0 / 0 / 13 | 295 / 0 / 1 / 294 |
| `"knowledge graph"` | 11 / 0 / 0 / 11 | 300 / 1 / 0 / 299 |
| GNN ∪ KG (the proposed addition) | 24 / 0 / 0 / 24 | 583 / 1 / 1 / 581 |
| `"stock"` (= `"stocks"`) | 2 / 0 / 0 / 2 | 44 / 0 / 6 / 38 |
| `"stock prediction"` | 0 | 0 |
| `"stock movement"` | 0 | 0 |
| `"equity"` (= `"equities"`) | 1 / 0 / 0 / 1 | 48 / 1 / 7 / 40 |
| `"lead-lag"` | 0 | 3 / 0 / 0 / 3 |
| `"correlation graph"` | 0 | 0 |
| `"asset returns"` | 0 | 0 |
| cs.SI, today's term filter | 0 | 11 / 0 / 6 / 5 |
| *extra:* `"stock return"` | 0 | 1 / 0 / 1 / 0 |
| *extra:* `"investor"` | 0 | 2 / 0 / 2 / 0 |
| **Union of all terms above** | **27 / 0 / 0 / 27** | **685 / 1 / 18 / 666** |

Overlap between terms, 90 days:

- GNN and KG share 12 papers.
- `stock` and `equity` share 4: MAPLE, Forecast Collapse, BRaG and AQuA.
- The one on-theme paper (OntoKG-EQ) appears under both `equity` and `knowledge graph`.
- In the 7-day window no paper matched more than one term.

The probe's other bare extras were counted but not classified. They are the forms SSRN already
rejected, and they are high-volume and mostly stemmed. 90-day counts: `"returns"` 717, `"market"`
200, `"momentum"` 124, `"supply chain"` 65, `"hedge"` 40. 7-day counts: 39, 10, 6, 2, 4.

## The on-theme paper

There is one, and it is weak:

- **2609.08869**, *OntoKG-EQ: A provenance-grounded, competency-question-governed knowledge graph
  for auditable analyst querying* (terms: `equity`, `knowledge graph`). It uses a KG built from
  emerging-market equity data (Pakistan, Malaysia, …) to answer analyst questions reproducibly.
  - The KG serves as query and provenance infrastructure. It is not a predictive signal, and the
    paper does not compare against a no-graph baseline.
  - It is also single-region empirics, which `## Reject` lists.
  - It is unlikely to reach a score of 7.

The 90-day windows contain **no** GNN, KG, lead-lag or correlation-graph paper on financial data that
the current filter misses. So either every graph-finance paper already contains a finance term (the
same result SSRN showed), or it sits in `q-fin.*`, which is unfiltered.

## Off-theme AI-finance papers (the filter misses these, but they are not about graphs)

- `stock` / `equity`:
  - 2607.24131 MAPLE (multi-alpha portfolio construction)
  - 2608.14106 Forecast Collapse in Time-Series Foundation Models
  - 2608.15770 BRaG (stock trading via inverse RL)
  - 2608.12841 AQuA (quant research agents)
  - 2608.28060 STRATA (cross-sectional A-share return ranking)
  - 2609.02797 Dutch Books for Language Models (uses stock-return events)
  - 2608.25717 RAG geo-bias over public companies
  - 2608.09218 Score-driven filters (twelve equity indices)
  - 2607.19389 Eutopia (credit-lending fairness)
- `investor`:
  - 2608.20271 Solana memecoin rug pulls
  - 2606.25984 InvestPhilBench
- `graph neural network`:
  - 2609.01942 Bitcoin address clustering with GNNs. This is graph ML on a transaction graph, but it
    is forensics, not a signal.
- cs.SI:
  - 2607.04178 DeFi rkAMM
  - 2608.08497 SocialFiVis
  - 2607.05203 Finfluencers on TikTok
  - 2606.30395 ConsumerSim
  - 2608.28526 VC syndication network formation. Finance and network, but no AI.
  - 2609.07293 Payable-network supplier selection. Finance and network, but no AI.

## Notable false positives

- **GNN (294):**
  - molecular and crystal property prediction
  - power flow and power grids
  - traffic
  - EEG and fMRI
  - finite-element and PDE surrogates
  - circuits and netlists
  - wireless beamforming
  - GNN theory (oversmoothing, the WL hierarchy)
  - 2607.11107, a generic graph fraud detector
  - 2607.16769, a GNN surrogate for supply-chain *operations*
  - 2608.14856, security games
- **KG (299):**
  - KG completion and embedding
  - GraphRAG and KGQA
  - biomedical and clinical KGs
  - cyber-threat-intelligence KGs
  - Wikidata cleaning
  - ontology engineering
- **`stock` (38):**
  - 2609.19760 SabreAgent (lost-sales inventory, base-stock)
  - 2608.14096 and 2608.02343 (inventory)
  - biomass and carbon stock
  - 2609.17274 (registry "stock")
- **`equity` (40):**
  - health equity
  - fairness metamodels
  - DEI prompts
  - workforce scheduling
  - 2608.09586 ICM poker "prize equity"
- **`lead-lag` (3):**
  - 2609.08070 neural microcircuits
  - 2608.02633 epidemic inference
  - 2608.05238 time-series–language alignment

## Recommendation

**Add nothing to the arXiv line. `taste.md` is unchanged (0 lines of the 45-line cap).**

- **`abs:"graph neural network" OR abs:"knowledge graph"` fails the bar badly.** It would add about
  6.5 candidates a day (583 over 90 days). That is +17% on a lane of about 38 a day, and 99.7% of
  those candidates would be false positives the judge has to reject, all for one weak on-theme
  paper per quarter. For comparison:
  - the SSRN term `supply chain` was rejected at 40/40 FP;
  - `return predictability` was accepted at 1 on-theme / 0 FP.

  If it were added it would still cost 0 lines, because it fits on the last row of the arXiv line.
- **No other candidate is justified.**
  - `stock` has 86% FP and `equity` has 83% FP. Both are stemmed and both catch the inventory and
    fairness senses.
  - The narrow graph phrases (`lead-lag`, `correlation graph`, `stock movement`, `stock prediction`,
    `asset returns`) add nothing.
  - cs.SI with today's filter adds no AI-in-finance paper that is on-theme.
- **The graph taste is already served** by `q-fin.*` (unfiltered) and by the finance terms that graph
  papers on financial data already use. The new `## Prefer` line changes how the judge scores
  papers. It does not need a new recall term.

Follow-up worth a ticket of its own: the `stock`/`equity` extras show that the current filter misses
about 5 genuine cross-sectional stock-prediction papers per quarter, not about graphs (MAPLE,
Forecast Collapse, STRATA, BRaG, AQuA). As an offline hint, `"equity market"` appears in three of the
1,774 pooled extras here, and all three are AI-finance (MAPLE, BRaG, OntoKG-EQ). That is not an
arXiv measurement. A real `abs:"equity markets"` probe would be needed before acting on it (SPEC
§1.1).
