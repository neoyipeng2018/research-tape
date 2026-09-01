# taste.md — the only tuning surface. Hard cap 45 lines.

## Queries

arxiv: (cat:q-fin.* OR ((cat:cs.CE OR cat:cs.LG OR cat:cs.AI) AND (abs:"financial" OR abs:"finance"
  OR abs:"stock market" OR abs:"portfolio" OR abs:"asset pricing" OR abs:"credit risk"
  OR abs:"volatility" OR abs:"algorithmic trading" OR abs:"limit order book"
  OR abs:"market microstructure")))
ssrn: ai: ai, artificial intelligence, machine learning, deep learning, neural network, neural
  networks, large language model, large language models, language model, language models, foundation
  model, foundation models, llm, llms, transformer, transformers, reinforcement learning, nlp,
  natural language processing, generative ai, gpt, embeddings, agentic
  finance: financial, finance, stock, stocks, market, markets, portfolio, asset pricing, assets,
  asset management, credit, credit risk, volatility, trading, trader, limit order book, market
  microstructure, bank, banks, banking, investor, investors, investment, equity, equities, bond,
  bonds, loan, loans, lending, hedge fund, derivative, derivatives, option pricing, pricing,
  valuation, risk management, systemic risk, default risk, financial risk, market risk, fintech,
  insurance, accounting, earnings, monetary policy, securities, cryptocurrency, bitcoin, esg, fund,
  funds, capital, debt, liquidity, inflation, payments, hedging, financing, corporate finance,
  corporate governance, mergers, underwriting

## Prefer

- Methods a practitioner could run this quarter: released code, a named dataset, a stated setup.
- LLMs and agents doing real financial work, not finance used as a toy benchmark for an LLM paper.
- Results that update a prior: a negative result, a failed replication, a surprising direction.
- Microstructure, execution and portfolio construction grounded in real trades or real order books.
- Evaluation itself: how anyone knows a financial ML claim survives out of sample.

## Reject

- Another price predictor with no baseline, no transaction costs, no out-of-sample discipline.
- Surveys, literature reviews, roadmaps, position papers.
- Single-country or single-sector empirics with no transferable method.
- Papers where "AI" is framing in the abstract and the contribution is somewhere else.
- Pure theory with no data and no visible path to implementation.

## Bar

threshold: 7
cap: 6
