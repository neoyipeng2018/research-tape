# Judge prompts — decided against real output (ticket #5)

Config: `claude -p --model haiku --output-format json`, `ANTHROPIC_API_KEY` unset.
**Pass 1 runs three times; the median score wins.** Ties broken by stable candidate key.
Bar 7, cap 6.

## Pass 1 — triage (all candidates, one call, x3)

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

    Output one JSON object per line, no other text, no markdown fence:
    {"id": <int>, "score": <int 0-10>, "why": "<max 12 words, the reason for the score>"}

    CANDIDATES
    [{id}] ({source}) {title}
    {abstract, whitespace-collapsed, shortened to 900 chars}

## Pass 2 — why-it-matters (survivors only, one call)

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

    Output one JSON object per line, no other text:
    {"id": <int>, "sentence": "<the sentence>"}

    PAPERS
    [{id}] ({source}) {title}
    {abstract}

## Measured on 2026-08-19 (31 candidates: 8 arXiv, 23 SSRN of 1,514 scanned)

- Pass 1: ~31 candidates, 60-150s, 5-13K output tokens per run. Pass 2: ~35-80s.
- Score distribution is well spread, not bunched: 39% <=4, 39% at 5-6, 23% >=7.
- Single-run publish sets overlap 47% (worst 17%). Median-of-3 also 47% — the residual
  churn is a genuine five-way tie at 7.0, not model noise. Median removes outlier errors.
- Bar 8 is worse than bar 7: publish count swings 2-6 between identical runs.
- Pass-2 voice rules verified on 12 sentences: 0 semicolons, 11-18 words, 0 banned openers.
