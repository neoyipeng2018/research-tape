# GitHub-native votes and bot-raised PRs

Research for [#4](https://github.com/neoyipeng2018/research-tape/issues/4). Audited 2026-08-24 against
`neoyipeng2018/research-tape` itself.

**Verdict: all three work. GitHub can carry the whole feedback loop with no backend and no PAT.**
One repo setting has to be flipped, and one design assumption has to be dropped — there is no
timestamp on a ticked box, so the weekly job must not try to ask "what is new since last week".
Both are handled below.

Findings marked **[live]** were executed against this repo. Findings marked **[docs]** are quoted
from docs.github.com. Where the two disagree the live result wins and the gap is called out.

---

## 1. The daily vote issue

### Checkbox markup that round-trips

An issue body is stored and returned as raw markdown, byte for byte.

**[live]** Created issue #10 with a body containing emoji, links, backticks, HTML comments and LF
endings, then read it back with `GET /repos/{owner}/{repo}/issues/{n}`:

```
IDENTICAL: True
sent md5 9b34fd7ae51af0a210a7df8483122461
got  md5 9b34fd7ae51af0a210a7df8483122461
sent len 881  got len 881
CRLF in got: False
```

Nothing is normalised, re-wrapped, entity-escaped, or line-ending-converted. The body is a string
GitHub hands back unchanged, so anything you can write you can parse.

### Which markers GitHub actually treats as a checkbox

**[live]** Ran every plausible variant through `POST /markdown` (`mode: gfm`), which is GitHub's own
renderer, and inspected the HTML for `class="task-list-item"` + `<input type="checkbox">`:

| Written | Becomes a real checkbox? |
|---|---|
| `- [ ] x` / `- [x] x` / `- [X] x` | yes — `X` and `x` both render `checked` |
| `* [ ] x` / `* [x] x` | yes |
| `+ [ ] x` | yes |
| `-   [ ] x` (extra spaces) | yes |
| `  - [ ] x` (indented) | yes, nested |
| `- [ ]no space after bracket` | **no** — renders as literal text |
| `- [] empty brackets` | **no** |
| `` - [ ] `- [ ] literal in backticks` `` | yes, and the inner one is inert code |

Two consequences. A parser must accept `[-*+]` and both `x`/`X`, because a human hand-editing the
body may type any of them. And it must *require* the space after `]`, because without it GitHub
renders no checkbox at all — a parser laxer than GitHub would count a vote on a line the human can
never actually click.

### Keying items so ticks map back unambiguously

Put a trailing HTML comment on the checkbox line carrying the direction and the item's stable key.

**[live]** The placement is load-bearing and the failure is silent:

```
- [ ] emoji 👍 then comment <!--v:up:a:3-->     →  <li class="task-list-item"><input type="checkbox" …>
<!--v:up:a:2--> - [ ] leading comment           →  plain text, NO checkbox
```

A **leading** HTML comment destroys the task list item — the line stops being a list item at all, so
the human sees no box to tick. The comment must be **trailing**. HTML comments are invisible in the
rendered issue either way, so the key costs nothing visually.

This keying is what makes the parse order-independent: the key travels on the same physical line as
the box, so nothing depends on item position, heading text, or line numbers. Reordering the body,
editing a title, or deleting an item cannot mis-attribute a vote. It also guarantees every checkbox
line is textually unique, which matters because GitHub's click-to-toggle rewrites the body by
locating the line — duplicate lines are the known way to toggle the wrong box.

Keys must match `[^\s<>]+`. arXiv ids (`2508.01234v2`) and SSRN DOIs (`10.2139/ssrn.4912345`) already
do. A title-derived fallback key must be slugified into the same charset by the daily job.

### Two boxes per item, not one

**Two.** The loop needs three states — liked, disliked, did not look — and one box only encodes two.

The one-box alternatives are both worse. An unticked `- [ ] 👎 bad pick` conflates "this was good"
with "I never opened the issue", which is the majority case on any given day and would silently read
as approval. Pre-ticking `- [x] keep` and asking the human to untick rejects is worse still: it
manufactures positive evidence for every item the human ignored, and `taste.md` is capped at ~40
lines precisely so that only real evidence earns a line.

Two boxes cost 12 checkboxes for a 6-item day, which reads fine. Ticking both is a contradiction;
the parser drops that item rather than guessing (see the reference parser below).

---

## 2. Reading the ticks back

### The call

`GET /repos/{owner}/{repo}/issues/{issue_number}` → `.body`. That is the whole of it: one request
returns the current state of every box on that issue. No special media type is needed; the default
JSON response carries raw markdown. **[live]** confirmed above.

Discovery is `GET /repos/{owner}/{repo}/issues?labels=tape:vote&state=all`. **[live]** verified
against this repo — label filtering returns the issue regardless of open/closed state.

### There is no timestamp on a ticked box

This is the finding that constrains the design, and it is worth stating flatly.

**[live]** Ticking a box is an issue-body edit. Body edits produce **no timeline event and no issue
event at all**. After patching the body of issue #10:

```
GET /repos/…/issues/10/timeline  → event count: 0
GET /repos/…/issues/10/events    → event count: 0
```

For contrast, after a label, a comment and a close, the same timeline returns exactly those three,
each with a timestamp — and still nothing for the two body edits:

```
labeled    2026-08-24T14:40:11Z  scratch-consumed
commented  2026-08-24T14:40:12Z
closed     2026-08-24T14:43:25Z
```

`updated_at` is not a substitute. **[live]** posting a plain comment moved `updated_at` from
`14:43:26Z` to `14:44:30Z` without any box changing. It moves for comments, labels, closes and
edits alike, so it cannot tell you a vote happened.

**The one thing that does carry a timestamp** is the GraphQL edit history. **[live]**:

```graphql
{ repository(owner:"neoyipeng2018", name:"research-tape") { issue(number:10) {
    lastEditedAt
    userContentEdits(first:20) { totalCount nodes { editedAt editor { login } diff } } } } }
```

returns one node per revision, newest first, each with `editedAt`, the editor, and — despite the
field being named `diff` — the **complete body at that revision**. Diffing consecutive nodes
reconstructs exactly which box changed and when. It works from a workflow with the default token
(**[live]** the probe workflow ran this query successfully with only `issues: write`).

Two caveats before anyone builds on it. It is one extra GraphQL call per issue with full bodies in
the payload, so it is not free at 30 issues a week. And it was verified for edits made **through the
REST API**; whether GitHub's web-UI click-to-toggle records a `userContentEdits` entry the same way
was **not** verified here, and that is the path the human will actually use. Treat tick timestamps
as unavailable until someone confirms the UI path.

### How the weekly job knows what it has already consumed

**Recommendation: it doesn't track that at all. Read a rolling 30-day window every week.**

The ticket asks for a label, a state, or a marker comment. The better answer is to delete the
question. Each weekly run lists vote issues from the last 30 days, reads the current tick state of
all of them, and hands the whole window to the judge that proposes the `taste.md` diff. This is:

- **Correct for late ticks by construction.** A three-week-old issue ticked yesterday is inside the
  window, so it is read. No "have I seen this?" bookkeeping, and no dependence on the tick timestamp
  that section 2 just established does not exist. Every other scheme has to answer "what changed
  since last Monday?" and there is no reliable way to answer it.
- **Idempotent.** Reruns and backfills are safe; nothing is consumed, so nothing can be
  double-consumed or lost to a failed run.
- **Already the system's natural boundary.** The map prunes `candidates/*.json` after 30 days and
  the index shows the last 30 days. The vote window matching that needs no new concept.

The cost is that a vote influences several consecutive weekly runs rather than one. That is fine,
and arguably desirable: a rule only earns a `taste.md` line if it keeps being supported. It is also
self-limiting — once a rule is in `taste.md`, the judge sees it there and proposes something else.

**If a consumed-marker is wanted anyway, use a label** (`tape:counted`), not issue state and not a
marker comment. A label is one API call to add and one filter to read, `labeled` events are
timestamped in the timeline (**[live]** above), and applying it twice is harmless. Closing the issue
is worse: it contradicts the "tick whenever" promise by making the issue look finished and pushing
it out of the default issue list, and the human loses the affordance. (**[live]** ticking a box on a
*closed* issue does still work via the API, so closing is not fatal — just misleading.) A marker
comment is worst: it adds a notification per issue per week and needs comment parsing on top of body
parsing.

### Reference parser

Verified against the format in section 4, including the adversarial cases:

```python
import re

ROW = re.compile(
    r"^[ \t]*[-*+][ \t]+\[([ xX])\][ \t][^\n]*?<!--[ \t]*v:(up|down):([^\s<>]+?)[ \t]*-->[ \t]*$"
)

def read_votes(body):
    """{key: 'up'|'down'} for every unambiguously ticked item."""
    ticks = {}
    for line in body.splitlines():
        m = ROW.match(line)
        if m:
            ticks.setdefault(m.group(3), set())
            if m.group(1) in "xX":
                ticks[m.group(3)].add(m.group(2))
    return {k: v.pop() for k, v in ticks.items() if len(v) == 1}
```

Behaviour: both boxes ticked → dropped as contradictory. Neither ticked → absent, which is
"no opinion", distinct from a vote. Unparseable line → ignored. The daily job should also write the
day's key list into `tape/YYYY-MM-DD.json` so the weekly job can assert the keys it parsed match the
keys that were published, and warn on a mismatch rather than silently losing a vote to a mangled
body.

---

## 3. Opening the PR from Actions

### The permissions block

Minimum for the whole loop, verified end to end **[live]** by running a probe workflow in this repo:

```yaml
# daily: open the vote issue
permissions:
  contents: read        # actions/checkout
  issues: write         # create the issue, label it

# weekly: read votes, open the taste PR
permissions:
  contents: write       # create the branch, commit taste.md, push
  issues: read          # read vote issue bodies
  pull-requests: write  # POST /repos/{owner}/{repo}/pulls
```

**[docs]** "If you specify the access for any of these permissions, all of those that are not
specified are set to `none`."
([workflow syntax reference](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax))
So these blocks are complete, not additive to a default.

Note `pull-requests: write` covers the `POST /pulls` call only. The head branch has to exist first,
and creating and pushing it is a `contents: write` operation — **[docs]** "Create a reference" and
"Create or update file contents" both require "'Contents' repository permissions (write)"
([REST git/refs](https://docs.github.com/en/rest/git/refs),
[REST repos/contents](https://docs.github.com/en/rest/repos/contents)). The docs never state that
pairing in one place; it follows from combining those pages with
[REST pulls](https://docs.github.com/en/rest/pulls/pulls).

**[live]** Confirmed with the default `GITHUB_TOKEN` and the block above — every step of the loop
works:

```
ISSUE CREATE:  OK   https://github.com/neoyipeng2018/research-tape/issues/11
ISSUE READ:    OK
GRAPHQL EDITS: OK
LABEL:         OK
COMMENT:       OK
PUSH:          OK   (branch + commit)
```

Both a bot-created issue and a bot-created PR work with the default token. No PAT and no GitHub App
is needed anywhere in this loop.

### The one blocker: a repo setting, not a permission

**[live]** With `pull-requests: write` explicitly granted, creating the PR still failed:

```json
{"message":"GitHub Actions is not permitted to create or approve pull requests.",
 "documentation_url":"https://docs.github.com/rest/pulls/pulls#create-a-pull-request",
 "status":"403"}
```

The gate is **Settings → Actions → General → Workflow permissions → "Allow GitHub Actions to create
and approve pull requests"**, and **[docs]** "By default, when you create a new repository in your
personal account, workflows are not allowed to create or approve pull requests."
([managing Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository))

**[live]** This repo is currently in that default state:

```json
{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}
```

Flipping it to `true` and re-running the identical workflow created PR #13 authored by
`github-actions[bot]`. It was flipped back afterwards, so **the repo is still in the blocking state
and this must be turned on before the weekly job can work.** Note the REST field is named
`can_approve_pull_request_reviews` even though it gates *creation* — a real trap when scripting it:

```
gh api -X PUT /repos/{owner}/{repo}/actions/permissions/workflow \
  -F default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```

**[docs gap]** No docs.github.com page states this failure mode or the error string. The 403 text
above is from the API response, captured live here, not from documentation.

### Does the "no workflows on bot PRs" limitation matter? No — but the rule has changed

**[docs]** The current rule, from both the
[GITHUB_TOKEN concept page](https://docs.github.com/en/actions/concepts/security/github_token) and
[triggering a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow):

> "When you use the repository's `GITHUB_TOKEN` to perform tasks, events triggered by the
> `GITHUB_TOKEN` will not create a new workflow run, with the following exceptions: `workflow_dispatch`
> and `repository_dispatch` events always create workflow runs. `pull_request` events with the
> `opened`, `synchronize`, or `reopened` activity types: when a workflow using `GITHUB_TOKEN` creates
> or updates a pull request, the resulting `pull_request` event creates workflow runs in an
> approval-required state."

So the blanket "bot PRs never trigger CI" is now out of date: runs *are* created for
`opened`/`synchronize`/`reopened`, they just sit waiting for a human to click "Approve workflows to
run". Either way it is irrelevant here — **nothing in this loop needs CI on the taste PR.** The PR
edits one file, `taste.md`, and its entire purpose is for a human to read a prose diff and merge or
close it. The human is already in the loop by construction; an approval button in front of a
non-existent test suite costs nothing.

Two consequences to keep in mind rather than act on:

- The daily `push` that publishes `tape/YYYY-MM-DD.json` will **not** trigger any `push` workflow.
  If a later ticket wants a rebuild-on-publish step, it must live in the same job, not a downstream
  workflow. **[docs]** "if a workflow run pushes code using the repository's `GITHUB_TOKEN`, a new
  workflow will not run even when the repository contains a workflow configured to run when `push`
  events occur."
- The same setting also blocks a bot **approving** a PR, so the bot cannot self-approve past a
  required-review rule. Fine — merging the taste PR is meant to be the human's decision.

**[docs]** There is no `workflows` permission scope, so `GITHUB_TOKEN` can never commit changes to
`.github/workflows`. The weekly PR only touches `taste.md`, so this does not bite — but it does mean
the loop can never modify its own workflows, which is a useful safety property to have for free.

---

## 4. Recommended vote issue body, verbatim

Title: `Tape 2026-08-24` · Label: `tape:vote`

```markdown
<!--tape:2026-08-24-->
Tick whatever you have an opinion on — both boxes, one box, or neither. Nothing here blocks publication; the weekly taste PR reads whatever is ticked when it runs.

### [Deep Hedging of Derivatives Using Reinforcement Learning](https://arxiv.org/abs/2508.01234)

`arXiv` · Frames hedging as an RL control problem, which matters because it drops the closed-form requirement that blocks most exotic books.

- [ ] 👍 more like this <!--v:up:arxiv:2508.01234-->
- [ ] 👎 less like this <!--v:down:arxiv:2508.01234-->

### [Retail Order Flow and Predictable Returns](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4912345)

`SSRN` · Puts a tradable lag between retail flow and price, which matters because it dates an anomaly everyone assumed was arbitraged away.

- [ ] 👍 more like this <!--v:up:ssrn:10.2139/ssrn.4912345-->
- [ ] 👎 less like this <!--v:down:ssrn:10.2139/ssrn.4912345-->
```

**[live]** Rendered through `POST /markdown` (GitHub's own GFM renderer). Every vote line becomes a
real `<li class="task-list-item">` with an `<input type="checkbox">`; both HTML comments and the
`<!--tape:…-->` header are invisible; the source badge stays a `<code>` span:

```html
<h3><a href="https://arxiv.org/abs/2508.01234">Deep Hedging of Derivatives Using Reinforcement Learning</a></h3>
<p><code>arXiv</code> · Frames hedging as an RL control problem, …</p>
<ul class="contains-task-list">
<li class="task-list-item"><input type="checkbox" class="task-list-item-checkbox"> 👍 more like this </li>
<li class="task-list-item"><input type="checkbox" class="task-list-item-checkbox"> 👎 less like this </li>
</ul>
```

Rules the generator must hold to:

1. The key comment is **trailing**, never leading — a leading comment silently kills the checkbox.
2. Exactly one space after `]`.
3. Keys match `[^\s<>]+`; slugify any title-derived fallback key.
4. Never emit two identical checkbox lines. The key comment guarantees this for free.
5. `<!--tape:YYYY-MM-DD-->` on line 1 so the parser can assert it is looking at a vote issue and get
   the tape date without trusting the title or `created_at` (which diverge on a backfill).

---

## 5. Should the design change?

**No.** All three mechanisms work as the map assumes, and the parts that are ugly are ugly in ways
that cost nothing here. Two things to carry into `SPEC.md`:

1. **Turn on "Allow GitHub Actions to create and approve pull requests"** before the weekly job
   ships. It is off right now. Everything else in the loop already works with the default token.
2. **The weekly job reads a rolling 30-day window; it does not track consumption.** This is the one
   place the ticket's framing should be dropped rather than answered — asking "which issues have I
   already consumed" only makes sense if you can tell when a tick happened, and you cannot.

### The alternative, if the missing timestamp ever becomes a problem

Swap checkboxes for **reactions on per-item comments**: the bot posts the day's items in the issue
body as now, plus one comment per item; the human reacts 👍/👎 on the comment.

**[live]** verified reactions carry exactly what checkboxes lack:

```
GET /repos/…/issues/10/reactions
+1   2026-08-24T14:45:17Z   neoyipeng2018
```

Every reaction has a `created_at` and a user. Nothing parses a body, so no markup can be mangled by
a hand-edit, and a vote is one click rather than an edit. The cost is 7 API objects per day instead
of 1 and a noisier issue.

Not recommended now — it trades a real cost for a timestamp nothing currently needs, and the rolling
window makes the timestamp unnecessary. Worth revisiting only if the "did-it-matter-later" signal on
the map lands and starts needing to know *when* an opinion was formed.

---

## Appendix: what was executed

Against `neoyipeng2018/research-tape`, 2026-08-24. All scratch artifacts (issues #10/#11, PR #13,
branches `scratch/*`, label `scratch-consumed`) were cleaned up and the workflow-permissions setting
was restored to its original value.

| # | Check | Result |
|---|---|---|
| 1 | `POST /markdown` on 14 checkbox variants | `-`/`*`/`+`, `x`/`X` all valid; no space after `]` and leading HTML comment both break it |
| 2 | Create issue, `GET` body back | byte-identical, md5 match |
| 3 | `PATCH` body to tick a box | succeeds; `updated_at` bumps |
| 4 | `GET .../timeline` and `.../events` after body edit | **0 events** |
| 5 | `POST` a comment | `updated_at` bumps with no box change |
| 6 | GraphQL `userContentEdits` | 2 nodes, `editedAt` + full body per revision |
| 7 | Probe workflow, default token, explicit `permissions:` | issue create / read / label / comment / branch+push all OK |
| 8 | Same workflow, `POST /pulls` | **403** "GitHub Actions is not permitted to create or approve pull requests" |
| 9 | Setting flipped on, workflow re-run | PR #13 created by `github-actions[bot]` |
| 10 | Tick a box on a **closed** issue | succeeds |
| 11 | `POST` a reaction, read back | carries `created_at` + user |
| 12 | Reference parser vs 17 assertions | passes; caught that a lax regex counts unclickable boxes |
