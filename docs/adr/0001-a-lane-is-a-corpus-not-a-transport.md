# A lane is a corpus, not a transport

From 2026-09-11, arXiv's edge answered the GitHub runner `406` on every request while the
identical query succeeded from a residential IP. The arXiv lane produced nothing for ten
days, and because a degraded lane is designed to exit 0, the tape went on publishing from
SSRN alone — the bar and the six-item cap selecting from half the intended pool, with the
page still claiming "arXiv + SSRN" underneath. The same wave of 406s was reported by at
least five other repositories harvesting arXiv from Actions runners in the same window;
arXiv announced nothing and `status.arxiv.org` still shows nothing.

We decided a **lane is the corpus it draws from, not the host it arrives through**. "arXiv"
names the papers; `export.arxiv.org` is one way to reach them and may be joined or replaced
by others (DataCite's `10.48550` prefix carries arXiv metadata with abstracts and
categories, on someone else's infrastructure entirely). A lane is dead only when *every*
transport for that corpus has failed. The alternative — naming lanes after transports, as
the glossary originally did — makes a vendor change look like an architecture change and
would have us calling a second arXiv route a third lane, with its own streak, its own note
and its own row in every tape.

**Consequences.** `fetch-arxiv.py` may grow transports that are not arXiv's API, and a
future reader finding DataCite inside a file of that name should read this rather than
"fix" it. The SSRN lane's notes now say "SSRN lane unreachable via Crossref" rather than
"Crossref lane", because the corpus is what failed the reader and the transport is only
why. `dead_days()` counts by the `source` written on a candidate, which is the corpus name,
so it keeps working unchanged when a corpus gains a second way in.

**Rejected: OAI-PMH on `oaipmh.arxiv.org`.** It is arXiv's own documented route for daily
incremental harvest and genuinely a different host, but it filters by set and date only —
no abstract search. Taking it would move the `abs:` half of the query out of `taste.md` and
into Python, putting taste in two places. That is the one thing `taste.md` exists to prevent.
