# taste.md — seed draft (prototype, ticket #5)

## Queries

arxiv: (cat:q-fin.* OR ((cat:cs.CE OR cat:cs.LG OR cat:cs.AI) AND (abs:"financial" OR abs:"finance"
  OR abs:"stock market" OR abs:"portfolio" OR abs:"asset pricing" OR abs:"credit risk"
  OR abs:"volatility" OR abs:"algorithmic trading" OR abs:"limit order book"
  OR abs:"market microstructure")))
ssrn: AI term anywhere AND finance term in title

## Prefer

- Methods a practitioner could run this quarter: released code, a named dataset, a stated setup.
- LLMs and agents doing real financial work, not finance used as a toy benchmark for an LLM paper.
- Results that update a prior: a negative result, a failed replication, a surprising direction.
- Microstructure, execution and portfolio construction grounded in real trades or real order books.
- Evaluation itself: how anyone knows a financial ML claim survives out of sample.
- A real financial task on real financial text or real market data beats a general ML
  method that merely uses a finance dataset.

## Reject

- Another price predictor with no baseline, no transaction costs, no out-of-sample discipline.
- Surveys, literature reviews, roadmaps, position papers.
- Single-country or single-sector empirics with no transferable method.
- Papers where "AI" is framing in the abstract and the contribution is somewhere else.
- Pure theory with no data and no visible path to implementation.
- Finance as the dataset rather than the problem — adoption studies, ESG scoring, anything
  where swapping in another domain would change nothing.

## Bar

threshold: 7
cap: 6
