# A day has one judge

From 2026-10-17 the judge moves off `claude -p --model haiku` and onto free OpenRouter models,
because Haiku's calls were spending subscription limits wanted for other work. Free models
come and go without notice and throttle under load, so a single pinned model would take days
dark, and OpenRouter's `openrouter/free` router would absorb that for us.

We decided against the router. The judge is a **pinned, ordered chain** — four free models,
vendors interleaved, then Haiku — and **a day is judged by exactly one link of it**. If a link
fails at any step, triage run 1 starts again under the next link; nothing is carried over.
Triage takes the median of three runs and the bar is one number in `taste.md`; both only mean
something when every score on a day comes from the same model on the same scale. A router can
answer three runs with three models, and its pool can admit a model whose 7 is Haiku's 5 on
precisely the days nobody is watching.

**Consequences.** A model joins the chain only after a shadow week beside the current judge:
its publish-set overlap must sit near Haiku's own run-to-run 47%, and its claims are read side
by side. The chain is edited by hand; a pulled model (404) is skipped on the day, never
replaced automatically. The day's judge is recorded in the candidates file and on the vote
issue. A day judged further down the chain is not a degraded day. Free endpoints require the
OpenRouter account's data policy to allow logging providers; when it does not, every link
answers 404 at once, which looks like the whole free pool vanishing.

**Rejected: per-model score offsets.** Correcting each link's scale onto Haiku's would let
weaker models join, but it puts part of the bar in Python and outside `taste.md`.

**After the shadow week (2026-10-18 to 10-22): the chain is `nemotron-3.5-super-vl:free`, then
Haiku.** Both Gemmas were rate-limited upstream on all five days, so there is no evidence about how
they judge. nemotron-3-super finished two days and matched 1 of Haiku's 5 picks. VL finished four
and picked 10 of Haiku's 13. It also scores about a point higher than Haiku: its count at 8 or
above tracks Haiku's at 7 or above. **The bar stays at 7 anyway, by choice:** on a VL day the cap of
6 does most of the selecting, and six a day is a tape the reader wants. On a day that falls back
to Haiku, the same 7 publishes fewer. That asymmetry is the price of one bar with no offsets.
