# Does arXiv ever clear the bar — 5 real days, median-of-3

PROTOTYPE, throwaway. Seed `taste.md`, `claude -p --model haiku`, pass 1 only, bar=7 cap=6.

| day | n | arXiv | SSRN | published | arXiv slots | med arXiv | med SSRN |
|---|---|---|---|---|---|---|---|
| 2026-08-12 | 35 | 21 | 14 | 5 | **4** | 5 | 3.0 |
| 2026-08-13 | 32 | 11 | 21 | 3 | **1** | 5 | 2 |
| 2026-08-14 | 23 | 12 | 11 | 2 | **2** | 4.0 | 2 |
| 2026-08-17 | 30 | 11 | 19 | 6 | **3** | 6 | 3 |
| 2026-08-18 | 37 | 16 | 21 | 4 | **3** | 4.0 | 2 |

## Score distribution

| score | arXiv | SSRN |
|---|---|---|
| 9 | 0 | 1 |
| 8 | 5 | 4 |
| 7 <= BAR | 8 | 2 |
| 6 | 13 | 5 |
| 5 | 13 | 6 |
| 4 | 11 | 11 |
| 3 | 3 | 12 |
| 2 | 11 | 26 |
| 1 | 4 | 11 |
| 0 | 3 | 8 |

arXiv: n=71 median=5 mean=4.48 >=7=13 (18%)

SSRN: n=86 median=2.0 mean=3.00 >=7=7 (8%)

## Every item that cleared 7

| day | median | src | runs | title |
|---|---|---|---|---|
| 2026-08-12 | 8 | SSRN | [8, 8, 9] | [Long-Horizon Forecasting of Complete Financial Statements with Forma](https://www.ssrn.com/abstract=7261138) |
| 2026-08-12 | 7 | arXiv | [6, 7, 7] | [Regime-Gated Residual Mixture-of-Experts for Cross-Sectional Volatility Forecast](https://arxiv.org/abs/2608.12251v1) |
| 2026-08-12 | 7 | arXiv | [7, 7, 8] | [Calibration Bets on the Past: Post-Training Quantization for Financial Time-Seri](https://arxiv.org/abs/2608.12259v1) |
| 2026-08-12 | 7 | arXiv | [7, 8, 6] | [GRPO for Financial Advice Generation: Outperforming Commercial LLMs under CATE E](https://arxiv.org/abs/2608.11787v1) |
| 2026-08-12 | 7 | arXiv | [5, 7, 7] | [FrontierFinance: A Challenging Benchmark for Measuring Frontier Intelligence of ](https://arxiv.org/abs/2608.11683v1) |
| 2026-08-13 | 9 | SSRN | [8, 9, 9] | [Version Migration as a Correlated Shock: Model Updates as an Unmanaged Risk Chan](https://www.ssrn.com/abstract=7256418) |
| 2026-08-13 | 8 | SSRN | [7, 8, 8] | [All Sizzle, No Steak? Do Macro Predictors and Sample Choices Improve Machine Lea](https://www.ssrn.com/abstract=7265723) |
| 2026-08-13 | 7 | arXiv | [7, 5, 7] | [FlowLOB: Efficient and Controllable Limit Order Book Generation with Flow Matchi](https://arxiv.org/abs/2608.13096v1) |
| 2026-08-14 | 8 | arXiv | [8, 8, 7] | [Buy the Rumor, Sell the News: When Is News Priced In?](https://arxiv.org/abs/2608.14014v1) |
| 2026-08-14 | 7 | arXiv | [8, 7, 7] | [Disclosed Human-Capital Disruption and Firm-Specific Risk](https://arxiv.org/abs/2608.14859v1) |
| 2026-08-17 | 8 | arXiv | [8, 8, 8] | [zLend: A Dual-Scope Cash-Flow Reconstruction Framework for On-Chain Credit Under](https://arxiv.org/abs/2608.16856v1) |
| 2026-08-17 | 8 | arXiv | [9, 8, 7] | [Governance at the Boundary: How Agent Decomposition Degrades Policy Compliance](https://arxiv.org/abs/2608.16055v1) |
| 2026-08-17 | 8 | SSRN | [8, 8, 6] | [Generative AI Service Outages and Price Impact in Cryptocurrency Markets](https://www.ssrn.com/abstract=7300331) |
| 2026-08-17 | 8 | SSRN | [9, 8, 8] | [Official Monetary Policy Narratives and Bond Risk Premia: Evidence from LLM-Base](https://www.ssrn.com/abstract=7300783) |
| 2026-08-17 | 7 | arXiv | [9, 7, 7] | [What Do Compliance Detectors Read? An Audit of Activation Probes and Guard Model](https://arxiv.org/abs/2608.16852v1) |
| 2026-08-17 | 7 | SSRN | [7, 8, 7] | [Does Generative AI Increase Investment Convergence?](https://www.ssrn.com/abstract=7294279) |
| 2026-08-18 | 8 | arXiv | [8, 8, 7] | [Temporal Leakage in Financial News NLP: A Multi-Architecture Audit with a Regime](https://arxiv.org/abs/2608.17223v1) |
| 2026-08-18 | 8 | arXiv | [7, 8, 8] | [Auditing Self-Evolution in Financial Agents: Capability Gains, Security Drift, a](https://arxiv.org/abs/2608.17684v1) |
| 2026-08-18 | 7 | arXiv | [7, 7, 7] | [PACE: Policy-Attested Contract Execution for Safe AI Agents in Decentralized Fin](https://arxiv.org/abs/2608.17220v1) |
| 2026-08-18 | 7 | SSRN | [6, 7, 7] | [Debt Prices the Opportunity Too: Generative AI in China’s Credit Market](https://www.ssrn.com/abstract=7307251) |

## Verdict

arXiv clears the bar routinely and **outscores SSRN**: 18% of arXiv candidates reach 7
against 8% of SSRN, median 5 against 2, and arXiv took 13 of the 20 published slots across
the five days — publishing on every one of them.

The 0-of-8 arXiv result on 2026-08-19 was a thin arXiv day (8 candidates against 11-21 here),
not a judge biased toward SSRN's backtest-result abstract style. The style-bias hypothesis is
refuted by what actually clears: benchmarks (`FrontierFinance`), audits (`Temporal Leakage in
Financial News NLP`, `What Do Compliance Detectors Read?`), and tooling (`FlowLOB`) all publish.
The seed `taste.md` line "Evaluation itself: how anyone knows a financial ML claim survives out
of sample" is already doing that work.

No change: no `taste.md` edit, no per-source floor, no per-source bar. The filtered `cs.*` lane
kept by ticket #14 is what pays here.

Incidental: SSRN's median of 2.0 is far below arXiv's 5 — the Crossref title-keyword filter
admits considerably more off-domain material than the arXiv query does. The judge absorbs it,
so nothing is owed, but SSRN is the noisy lane, not arXiv.
