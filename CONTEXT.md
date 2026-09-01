# CONTEXT.md

The vocabulary of this repo. Glossary only — mechanics live in [SPEC.md](SPEC.md).

**Tape** — the published output for one day: at most six items, ordered, rendered on the site and
stored as `tape/YYYY-MM-DD.json`. The archive and the never-republish index are the same files.

**Item** — one published paper on the tape. Four fields and no more: title, link, source, claim.

**Claim** — the why-it-matters sentence. It asserts something a reader could disagree with, rather
than summarising the paper. On the page the claim *is* the item; the title is where you go next.

**Candidate** — a paper fetched from a source lane on a given day and scored by the judge. Every
candidate is stored in `candidates/YYYY-MM-DD.json` whether it published or not, and pruned after
30 days.

**Key** — a candidate's identity: the bare arXiv id (version suffix stripped) or the SSRN DOI. A key
that has published never publishes again.

**Fingerprint** — the set of 4+ character lowercase word tokens in a candidate's abstract. Two
candidates whose fingerprints overlap enough are the same paper under two keys.

**Lane** — one source query: arXiv or SSRN-via-Crossref. A lane can be down without the day going
dark.

**Judge** — the model that scores candidates and writes claims. Two passes: triage scores everything,
then claims are written for survivors only.

**Bar** — the score a candidate must reach to publish, and the cap on how many may publish in a day.
Both live in `taste.md`.

**Taste** — `taste.md`: the queries, the preferences, the rejections and the bar. The only file the
loop is ever allowed to change about itself, capped at 45 lines so a new rule must retire an old one.

**Vote** — a ticked checkbox on a day's vote issue: 👍 or 👎 against one published item. A vote carries
no timestamp; it is read by the issue it sits on.

**Vote issue** — the issue opened every day the loop runs, holding that day's items as a checklist.
It is also the heartbeat: its arrival is the proof the loop is alive.

**Taste PR** — the monthly pull request proposing at most three line changes to `taste.md`, argued
from votes. There is only ever one open.

**Quiet day** — the loop ran and nothing cleared the bar. An empty tape file is committed and the
page says so.

**Dark day** — the loop did not run, or failed. Nothing is written; the site keeps yesterday's tape.
