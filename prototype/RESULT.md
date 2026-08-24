# Judge calibration run — 2026-08-19 candidates

PROTOTYPE, throwaway. Seed `taste.md`, `claude -p --model haiku`, two passes.

n=31 (8 arXiv, 23 SSRN of 1,514 SSRN DOIs scanned). bar=7, cap=6.

## Distribution

```
10 |            | 0
 9 |#           | 1
 8 |#           | 1
 7 |#####       | 5   <= BAR
 6 |#########   | 9
 5 |###         | 3
 4 |###         | 3
 3 |###         | 3
 2 |###         | 3
 1 |###         | 3
 0 |            | 0

>=7: 7   5-6: 12   <=4: 12
```

## Every candidate

| # | src | title | why | tape sentence |
|---|---|---|---|---|
| **9** | SSRN | When Text Becomes Tradable: Financial-domain Language Models and [...] | FinBERT on ag futures news 2009-2023; Sharpe 2.5, out-of-sample validated. | Financial-domain language models extract tradable signals from commodity news; FinBERT achieves 2.5 Sharpe on agricultural futures long-short portfolios. |
| **8** | SSRN | Hedge and Seek: A Q-Learning Approach to Dynamic Hedging of the [...] | Real hedging via RL on live futures; 2007-2022 backtest, beats baselines. | Reinforcement learning dynamic hedging outperforms minimum-variance benchmarks; macro factors including credit conditions and yield curve optimize hedge ratios. |
| **7** | SSRN | Do Banks Really Know What They Get From AI? | Banks' AI ROI unverifiable from public data; important reality check. | Ten major U.S. banks claim AI cost savings but provide no public cost data to verify financial benefit. |
| **7** | SSRN | The Price of Greenwashing: Algorithmic Verification and Market [...] | Greenwashing detection via XGBoost+Conformal on real SEC/EPA data. | Facility-level emissions data enables algorithmic detection of greenwashing; XGBoost models quantify forecast uncertainty with conformal prediction confidence bands. |
| **7** | SSRN | AutoScientist-Quant: Self-Evolving Coding Agents for Automatic [...] | Self-adaptive LLM agent for alpha discovery; budgeted search, prevents leakage. | Automated agents close alpha discovery loop: end-to-end pipeline eliminates manual model selection and prevents data-leakage overfitting. |
| **7** | SSRN | The Clock of Regimes: An Operator-Theoretic Early-Warning System [...] | Post-mortem on SituationalAwareness collapse; real fund, concentration warning. | Operator-theoretic regime framework detected stress signals before July 2026 AI fund collapse; concentrated positions showed extreme correlation and leverage risk. |
| **7** | SSRN | Do Banks Really Know What They Get From AI? | Banks' AI ROI unverifiable from public data; important reality check. |  |
| **6** | SSRN | FinRCA-Bench: Separating Retrieval Failure from Reasoning [...] | Duplicate of [4]; synthetic reconciliation benchmark. |  |
| **6** | SSRN | Accurate but Correlated:&nbsp;Common AI Forecast Errors and [...] | Theory: coordinated AI models increase forecast error covariance systemically. |  |
| **6** | SSRN | Contingent Winners: Forecast Scale and Model Rankings in [...] | Model selection regime bias in volatility forecasting; documents but doesn't solve. |  |
| **6** | SSRN | Agentic Artificial Intelligence and Systemic Financial Risk: A [...] | Framework for agentic AI systemic risk; timely but not yet empirically validated. |  |
| **6** | SSRN | Chips as Collateral: Vendor-Supported Chip-Backed Debt and the [...] | GPU-backed lending structure observation (Apollo-xAI); descriptive, not tradable. |  |
| **6** | SSRN | Explainable Artificial Intelligence for Dynamic Credit Risk [...] | Credit risk with macro time series (X-DyAR); design sound but no backtest results. |  |
| **6** | arXiv | Concentrated Liquidity Provision: a Reinforcement Learning Perspective | Real DeFi problem (LP rebalancing) but no out-of-sample backtest shown. |  |
| **6** | arXiv | FinRCA-Bench: Benchmarking Evidence Retrieval and Reasoning for [...] | Synthetic benchmark for reconciliation; infrastructure not method. |  |
| **6** | arXiv | Converting Expert Deliberation into Financial Signals Through A [...] | Real LLM+finance (investment committee); 73% accuracy but no transaction costs. |  |
| **5** | SSRN | Stranded Credentials: How A Skill-Signaling Market Absorbed [...] | Kaggle medals predict performance through AI transition; not finance. |  |
| **5** | arXiv | Deep-MKV-TS: Path-Dependent McKean--Vlasov Control for Financial [...] | Scenario generation with neural SMP, validated on synthetic models only. |  |
| **5** | arXiv | Quantifying Event Impacts on Time Series via Multiscale [...] | Event-to-loss prediction pipeline; real problem but no proof or code. |  |
| **4** | SSRN | A Hybrid LSTM-GARCH Framework for Short-Horizon Stock Price [...] | LSTM-GARCH on NIFTY50; single-country, no transaction costs. |  |
| **4** | SSRN | The Effects of Artificial Intelligence Engagement on Socially [...] | AI engagement vs ESG across 136 banks; correlation, not method. |  |
| **4** | arXiv | Test-Time Scaling in the Wild: Why Exploitation, Not [...] | Finance one of five benchmarks; AI framing not core contribution. |  |
| **3** | SSRN | Online Appendix to 'Targeting Additionality - A Theory of [...] | Appendix on blended finance; infrastructure only. |  |
| **3** | SSRN | Stock Price Prediction Using ML Techniques | BiLSTM+Transformer on CSI-300; generic predictor, no baselines. |  |
| **3** | arXiv | Tuning the Stochastic Machine: A Systems Engineer's Operating [...] | LLM governance framework; off-topic for finance practitioner. |  |
| **2** | SSRN | AI Adoption in Emerging Markets — Productivity Effects, [...] | AI adoption in emerging markets; development econ, not finance. |  |
| **2** | SSRN | The Economics of Climate Stabilization: Investment, Technology [...] | Climate stabilization macroeconomics; off-topic. |  |
| **2** | arXiv | When to Sell an Asset? - A Distribution Builder Approach | Pure theory on asset sale timing; no data or implementation. |  |
| **1** | SSRN | Reduced-Derivative Consistency: The Impact of Activation- [...] | Physics-informed neural networks; off-topic. |  |
| **1** | SSRN | Hope, Signals, and Silicon: A Game-Theoretic Model of the Pre- [...] | Game theory of academic labor; off-topic. |  |
| **1** | SSRN | Proposed Development and Validation of a Household Wedding [...] | Wedding expense protocol in Bangladesh; off-topic. |  |
