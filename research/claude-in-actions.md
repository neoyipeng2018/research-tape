# Running `claude -p` inside GitHub Actions

Research for [issue #3](https://github.com/neoyipeng2018/research-tape/issues/3). Verified 2026-08-24
against Claude Code CLI **v2.1.241** and the official docs at `code.claude.com`.

Everything marked **measured** was run on a real CLI against real arXiv `q-fin` abstracts, not
inferred from docs. Everything marked **documented** is quoted from a primary doc page. Two things
are marked **unverified** and say so.

The old repo's workflows (`my_life/.github/workflows/research-tape-{daily,skills,sentinel}.yml`) are
the starting point. Their probe pattern still works. Four other things in them are now wrong or were
always wrong; each is flagged below.

---

## 1. The auth token

`claude setup-token` opens the same browser flow as `/login` and prints a **one-year OAuth token** to
the terminal. It saves nothing — you copy it out yourself. It requires a Pro, Max, Team, or
Enterprise plan, and it can only make model requests: it cannot open Remote Control sessions or fetch
claude.ai connectors. ([authentication docs](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token))

Store it as the repository Actions secret `CLAUDE_CODE_OAUTH_TOKEN` and expose it as the environment
variable of the same name. On this path there is **no per-token bill** — runs consume the
subscription's usage limits, not API credits. `--model haiku` therefore conserves *usage limits*, not
dollars. (The docs put it plainly: "If you authenticate with an OAuth token, runs use your Claude
subscription instead of API billing." — [github-actions docs](https://code.claude.com/docs/en/github-actions#manage-costs).)
The `total_cost_usd` field the CLI returns is a client-side API-equivalent estimate, useful only as a
relative size signal; nobody is charged it.

### Trap 1: do not also set `ANTHROPIC_API_KEY`

Documented credential precedence is: cloud provider vars → `ANTHROPIC_AUTH_TOKEN` →
`ANTHROPIC_API_KEY` → `apiKeyHelper` → `CLAUDE_CODE_OAUTH_TOKEN` → profiles → `/login`.
([authentication docs](https://code.claude.com/docs/en/authentication#authentication-precedence))

The old workflows set **both** `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` on every job. If both
secrets exist, the API key silently wins and the run bills the API account instead of the
subscription. Set only the one you mean.

An unset secret expands to the empty string, and empty is treated as unset — **measured**: with
`ANTHROPIC_API_KEY=` and a valid OAuth token, the run authenticated via OAuth. So a stray empty
`ANTHROPIC_API_KEY:` line is harmless; a populated one is not.

### Trap 2: `--bare` cannot be used here

`--bare` is otherwise the right CI flag (skips hooks, plugins, MCP autodiscovery, CLAUDE.md) and the
docs call it "the recommended mode for scripted and SDK calls". But: "Bare mode does not read
`CLAUDE_CODE_OAUTH_TOKEN`. If your script passes `--bare`, authenticate with `ANTHROPIC_API_KEY` or an
`apiKeyHelper` instead." ([authentication docs](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token),
and `claude --help` says the same). On the subscription path, `--bare` is off the table. Section 2
gives the flags that recover most of its benefit.

### The probe

The old probe is sound and should be kept, with one fix:

```bash
probe() { timeout 120 claude -p "Reply with the single word ok" --output-format json > /tmp/claude-probe.json; }
probe || probe || { echo "Claude probe failed twice."; cat /tmp/claude-probe.json; exit 1; }
```

It passes **no `--model`**, so the probe runs on the account's default model — burning the Opus/Sonnet
limit bucket to answer a yes/no question. Add `--model haiku`. Otherwise the shape is right: run a
trivial prompt with a hard timeout before any real work, and fail the job immediately if it doesn't
come back clean. Section 7 has the fixed version.

Why it must check the JSON envelope and not just the exit code: see section 8.

---

## 2. The invocation

**Measured** hermetic flag set — this produced `n_tools 0`, `mcp_servers []`, and a fixed prompt
overhead of **3,398 tokens**:

```bash
claude -p \
  --model haiku \
  --system-prompt "You are a research-tape triage classifier. Return only the requested structured output." \
  --output-format json \
  --json-schema "$(cat schema/triage.json)" \
  --tools "" \
  --strict-mcp-config \
  --no-session-persistence \
  --max-turns 4 \
  < prompt.txt > triage.json
```

Flag by flag:

| Flag | Why |
|---|---|
| `--model haiku` | **Measured**: resolves to `claude-haiku-4-5-20251001`, `contextWindow: 200000`, `maxOutputTokens: 32000`, read straight out of the response envelope's `modelUsage`. |
| `--system-prompt` | *Replaces* the default Claude Code system prompt (`--append-system-prompt` adds to it). This is the single biggest lever: **measured**, dropping it took prompt overhead from 3,398 to 27,712 tokens. A triage classifier needs none of the coding-agent prompt. |
| `--tools ""` | Disables all built-in tools. **Measured**: cuts the tool list from 78 to 53 — the survivors were all `mcp__*`. It does *not* remove MCP tools on its own. |
| `--strict-mcp-config` | Ignores every MCP config except one passed via `--mcp-config`. Passing none means none. **Measured**: this is what takes the tool count to 0. A setup-token OAuth credential can't load claude.ai connectors anyway, but a repo's own `.mcp.json` *is* read under `-p` even in an untrusted folder — this is the flag that stops that. |
| `--no-session-persistence` | Nothing to resume; skips writing session files. |
| `--max-turns 4` | See trap 3. |
| prompt on **stdin** | Keeps a ~90 KB prompt off the argv length limit. Piped stdin is capped at 10 MB ([headless docs](https://code.claude.com/docs/en/headless#pipe-data-through-claude)). |

With zero tools there is nothing to prompt for permission on, so `--permission-mode` and
`--dangerously-skip-permissions` are both unnecessary. The old skills workflow used
`--permission-mode bypassPermissions` because those calls invoked repo skills that really did edit
files; a pure classification call should not.

Also set as job env: `DISABLE_AUTOUPDATER: "1"` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"`
(both carried over from the old workflows; they keep the CLI from updating itself mid-run or making
side calls).

### Trap 3: `--max-turns 1` breaks structured output

**Measured.** With `--json-schema`, the structured result is delivered as a tool call — the envelope
comes back with `"stop_reason": "tool_use"` and `num_turns` of at least 2. Running with `--max-turns 1`
returned:

```json
{"is_error": true, "subtype": "error_max_turns", "terminal_reason": "max_turns",
 "errors": ["Reached maximum number of turns (1)"]}
```

with exit code 1 and no scores. The 60-candidate run used `num_turns: 3`. Use `--max-turns 4` — enough
headroom, still a hard stop against a runaway loop.

### Trap 4: `--tools ""` in the old code was a no-op

The old Node helper built argv as `if (options.tools?.trim().length > 0) args.push("--tools", options.tools)`,
so passing `tools: ""` **omitted the flag entirely** and every judge call ran with the CLI's default
tool set. Pass `--tools ""` to the CLI directly; the CLI does honour an empty string.

---

## 3. Getting parseable JSON back

`--output-format json` with `--json-schema` puts the parsed object in the envelope's
**`structured_output`** field. No regex, no fence-stripping.
([headless docs](https://code.claude.com/docs/en/headless#get-structured-output))

**Measured** envelope from a successful run (top-level keys):

```
type subtype is_error result structured_output session_id uuid stop_reason terminal_reason
api_error_status num_turns duration_ms duration_api_ms ttft_ms ttft_stream_ms time_to_request_ms
total_cost_usd usage modelUsage permission_denials fast_mode_state fast_mode_disabled_reason
subagent_stats
```

`result` carries the same JSON *as a string*; `structured_output` is the object. Read
`structured_output` and skip the double parse:

```bash
jq '.structured_output.scores' triage.json
```

If the schema itself is invalid, `claude` exits before sending anything with
`Error: --json-schema is not a valid JSON Schema` plus the validator diagnostic. Schemas may use
`format` but it's an annotation only, not enforced.

The schema used for triage:

```json
{
  "type": "object",
  "properties": {
    "scores": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": { "id": {"type":"string"}, "score": {"type":"integer","minimum":0,"maximum":10} },
        "required": ["id","score"],
        "additionalProperties": false
      }
    }
  },
  "required": ["scores"],
  "additionalProperties": false
}
```

The schema constrains *shape*, not *completeness* — nothing in it forces one entry per input id. The
old repo solved this by baking the ids into `required`, which makes the schema itself enforce the
id set. That's worth copying if drops ever show up; **measured**, they didn't (60/60 ids returned, 0
missing, 0 extra), so the cheaper version is a post-hoc set comparison in the caller. Do the
comparison either way — it's the only thing standing between a silently short result and a thin tape.

---

## 4. One call or sixty?

**One call.** For ~60 candidates this isn't close.

**Measured token budget**, from a delta experiment (same prompt with 8 candidates vs 0 candidates,
subtracting the fixed overhead):

- **~336 tokens per candidate** (arXiv title + abstract; mean 1,416 characters over 8 real `q-fin`
  entries, max 1,856). Chars/4 predicts 354, so the rule of thumb is fine.
- 60 real candidates = 85,809 characters = an 89 KB prompt file.
- 60 × 336 ≈ **20K tokens**, plus ~3.4K fixed overhead ≈ **24K of the 200K window**. 12% full.

Context is not the binding constraint — **output tokens are**. The 60-candidate run emitted 9,687
output tokens, of which **7,205 were thinking**, against `maxOutputTokens: 32000`. At ~160 output
tokens per candidate the ceiling is roughly 200 candidates in one call, and thinking is what fills
it, not the scores. There is ~3x headroom at 60.

Against that, sixty separate calls would mean: 60 × 3.4K = **204K tokens of overhead re-sent** for
20K of actual content, 60 process startups (**measured** at ~5.5 s each for a trivial call, so ~5
minutes of pure startup), and 60 separate charges against the subscription's usage limits instead of
one. Per-item calls are strictly worse on every axis.

**The cost of batching** is that one bad call loses all 60. Two mitigations, in order of laziness:

1. Retry the whole call (section 6). At 110 s a retry is cheap.
2. If retries start failing regularly, split into **two batches of 30** and keep partial results.
   Don't go below that. The old repo ran `batchSize: 10` with a persisted per-batch cache, which is
   the fully paranoid version — it exists because that repo also ran 3 independent judging passes per
   item. This one doesn't.

Note the 60/60 result is an *availability* check, not a *quality* one — it says the model returns a
complete, well-formed set at that batch size, not that scores are as good as they'd be at batch 10.
If taste ever looks noisy, batch size is a variable to test before blaming the prompt.

---

## 5. Wall clock

**Measured**, 60 real arXiv candidates, one call, warm network:

| | |
|---|---|
| Wall clock, end to end | **110 s** |
| `duration_ms` / `duration_api_ms` | 106,839 / 106,767 ms |
| `ttft_ms` (time to first token) | 88,849 ms |
| `num_turns` | 3 |
| Output tokens | 9,687 (7,205 thinking) |
| Result | 60/60 ids scored, 0 missing, 0 extra |

Note the shape: 89 s of the 110 is time-to-first-token — the model thinks, then emits the whole
structured block quickly. A progress-free 90-second silence is normal, not a hang. Set timeouts well
above it.

Budget for a daily pass:

- `npm install -g @anthropic-ai/claude-code@latest`: ~20-40 s
- auth probe: ~5 s
- triage call: ~110 s, call it 180 s worst case
- pass 2 (why-it-matters for ≤6 survivors) will be a second, much smaller call

So: `timeout -k 30 600` on the triage call, `timeout-minutes: 15` on the step, `timeout-minutes: 30`
on the job. The whole daily loop should land in **under 5 minutes** of runner time.

---

## 6. Timeout and retry

**Timeout: wrap the call in coreutils `timeout`.** `ubuntu-latest` has it. (macOS does not, if you
test locally — `brew install coreutils` gives `gtimeout`.)

```bash
timeout -k 30 600 claude -p ...
```

Exit codes to know:

- **`timeout` returns 124** when it fires. It sends `SIGTERM` at 600 s, then `SIGKILL` 30 s later
  (`-k 30`) if the CLI ignores it.
- **`claude` itself exits 143 on SIGTERM**, and "leaves the turn that was in progress unfinished and
  records no result for it" ([headless docs](https://code.claude.com/docs/en/headless#stop-a-run-with-sigterm)).
  You'll see 124 from `timeout`; you'd see 143 only if something else killed the process.

**Retry: three attempts, linear backoff, but only for retryable classes.** The old repo retried
everything three times with `delay * attempt` (5 s, 10 s). Keep the shape, add the discrimination it
lacked: retrying a 401 three times just wastes 2 minutes, and retrying an exhausted usage limit
wastes the same and cannot succeed until the reset time. Both should fail the job on attempt one.

Retryable: timeout (124), 429/529, malformed or incomplete output, empty result.
Not retryable: 401 (auth dead), usage/weekly/session limit reached, credit balance too low.

The CLI already does its own internal retry with backoff underneath this — with
`--output-format stream-json` it emits `system/api_retry` events carrying `attempt`, `max_retries`,
`retry_delay_ms`, `error_status`, and an `error` category from a documented enum:
`authentication_failed`, `oauth_org_not_allowed`, `billing_error`, `rate_limit`, `overloaded`,
`invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `unknown`
([headless docs](https://code.claude.com/docs/en/headless#handle-api-retries)). Worth knowing that
enum exists, but reading a stream to get it is more machinery than a daily triage job needs. The
outer three-attempt loop is enough.

One measured surprise on latency: a **bogus `ANTHROPIC_API_KEY` took 180 seconds to fail** (the CLI
retried the 401 internally), while a **bogus `CLAUDE_CODE_OAUTH_TOKEN` failed in 2.4 seconds**. So
even the auth probe needs its own timeout — the old workflow's `timeout 120` was doing real work.

---

## 7. Workflow snippet

Self-contained, subscription-token path, no API key anywhere.

```yaml
name: Research Tape Daily

on:
  schedule:
    - cron: "0 22 * * *"   # 06:00 Singapore
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: research-tape-daily
  cancel-in-progress: false

env:
  CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
  DISABLE_AUTOUPDATER: "1"
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"

jobs:
  tape:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-node@v4
        with:
          node-version: "22"

      - name: Install Claude Code
        run: |
          npm install -g @anthropic-ai/claude-code@latest
          claude --version

      # Fail fast on dead auth before doing any real work.
      - name: Probe Claude auth
        run: |
          set -uo pipefail
          if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
            echo "::error::CLAUDE_CODE_OAUTH_TOKEN secret is not set."
            exit 1
          fi
          timeout -k 10 120 claude -p "Reply with the single word ok" \
            --model haiku \
            --system-prompt "Reply exactly as asked." \
            --output-format json --tools "" --strict-mcp-config \
            > /tmp/probe.json
          # Exit code alone is not enough: an auth failure still reports subtype "success".
          if ! jq -e '.is_error != true and ((.result // "") | length > 0)' /tmp/probe.json > /dev/null 2>&1; then
            echo "::error::Claude auth probe failed."
            jq -r '"api_error_status=\(.api_error_status // "none") result=\(.result // "no result")"' /tmp/probe.json 2>/dev/null || cat /tmp/probe.json
            exit 1
          fi
          echo "Claude auth OK."

      - name: Collect candidates
        run: ./scripts/fetch-candidates.sh > /tmp/candidates.json

      - name: Triage candidates
        timeout-minutes: 15
        run: |
          set -uo pipefail
          {
            cat taste.md
            echo
            echo "Score every candidate 0-10. Return exactly one entry per input id. No prose."
            echo
            cat /tmp/candidates.json
          } > /tmp/triage-prompt.txt

          triage() {
            timeout -k 30 600 claude -p \
              --model haiku \
              --system-prompt "You are a research-tape triage classifier. Return only the requested structured output." \
              --output-format json \
              --json-schema "$(cat schema/triage.json)" \
              --tools "" \
              --strict-mcp-config \
              --no-session-persistence \
              --max-turns 4 \
              < /tmp/triage-prompt.txt > /tmp/triage.json
          }

          ok=""; last="MALFORMED_OUTPUT"
          for attempt in 1 2 3; do
            triage; ec=$?

            if [ "$ec" -eq 0 ] && jq -e '.is_error != true and ((.structured_output.scores // []) | length) > 0' /tmp/triage.json > /dev/null 2>&1; then
              ok=yes; break
            fi

            status=$(jq -r '.api_error_status // ""' /tmp/triage.json 2>/dev/null)
            result=$(jq -r '.result // ""' /tmp/triage.json 2>/dev/null)
            echo "::warning::triage attempt ${attempt} failed (exit=${ec} api_error_status=${status:-none}): ${result:-no result}"

            # Hard stops: retrying cannot help.
            if [ "$status" = "401" ]; then
              echo "::error::AUTH_DEAD - CLAUDE_CODE_OAUTH_TOKEN rejected. Regenerate with 'claude setup-token'."
              exit 1
            fi
            case "$result" in
              *"usage limit"*|*"weekly limit"*|*"session limit"*|*"Credit balance"*|*"spend limit"*)
                echo "::error::LIMITS_EXHAUSTED - ${result}"
                exit 1 ;;
            esac
            if [ "$ec" -eq 124 ]; then last="CLI_HANG"; else last="MALFORMED_OUTPUT"; fi

            if [ "$attempt" -lt 3 ]; then sleep $((attempt * 30)); fi
          done

          if [ -z "$ok" ]; then
            echo "::error::${last} - no usable scores after 3 attempts."
            exit 1
          fi

          # The schema constrains shape, not completeness. Check the id set.
          got=$(jq '.structured_output.scores | length' /tmp/triage.json)
          want=$(jq 'length' /tmp/candidates.json)
          if [ "$got" -ne "$want" ]; then
            echo "::error::MALFORMED_OUTPUT - scored ${got} of ${want} candidates."
            exit 1
          fi

          jq '.structured_output.scores' /tmp/triage.json > /tmp/scores.json
          jq -r '"triage ok: \(.structured_output.scores | length) scored in \(.duration_ms / 1000 | floor)s, \(.usage.output_tokens) output tokens"' /tmp/triage.json
```

Pass 2 (why-it-matters for survivors) is the same block with a different schema, a different prompt,
and ≤6 items — small enough that it needs no batching thought at all.

`jq` is preinstalled on `ubuntu-latest`. The retry/classify block above was exercised against stubbed
envelopes for all five outcomes — clean success, 401, weekly-limit text, `timeout` exit 124, and a
well-formed envelope with no `structured_output` — and each took the intended branch: success and
both hard stops exit on attempt 1, the two retryable classes run three attempts and then fail with
their own label. Note the loop deliberately uses `set -uo pipefail` and **not** `set -e`: with `-e`,
the loop's final `[ "$attempt" -lt 3 ] && sleep …` test returns non-zero on the last iteration and
kills the step before the result gate ever runs.

`anthropics/claude-code-action@v1` is the officially recommended path for GitHub Actions and takes
`claude_code_oauth_token` plus a `claude_args` passthrough. It is built for *agentic* work in a repo —
`@claude` mentions, PR review, issue-to-PR. For a single non-interactive classification call it adds
an action, a GitHub App install, and an indirection layer over the same `claude -p` this snippet runs
directly. The docs explicitly support installing the CLI and calling it in a step. Use the plain CLI
here; reach for the action if the loop ever needs Claude to open its own PRs.

---

## 8. Failure taxonomy

The single most important finding, **measured**: on an authentication failure the envelope still
reports **`"subtype": "success"`**. Do not branch on `subtype`.

Full measured envelope for a bogus `CLAUDE_CODE_OAUTH_TOKEN`:

```json
{"is_error": true, "subtype": "success", "terminal_reason": "api_error",
 "api_error_status": 401, "total_cost_usd": 0, "modelUsage": {},
 "result": "Failed to authenticate. API Error: 401 OAuth access token is invalid."}
```

Exit code 1, stdout only, **stderr empty**. The docs match: "When a failure happens inside the run,
such as missing authentication, Claude Code prints the failure as the result on stdout."
The reliable discriminators are, in order: **exit code**, **`is_error`**, **`api_error_status`**,
**`result` text**.

| # | Failure | Exit | `is_error` | `api_error_status` | `result` text | Retry? | Action |
|---|---|---|---|---|---|---|---|
| 1 | **AUTH_DEAD** | 1 | `true` | `401` | `Failed to authenticate. API Error: 401 OAuth access token is invalid.` (measured) / `OAuth token has expired` / `OAuth token revoked` / `Login expired · Please run /login` (documented) | **No** | Fail the job. Regenerate with `claude setup-token`, update the secret. Token life is 1 year, so this is a calendar event, not a random fault. |
| 2 | **LIMITS_EXHAUSTED** | 1 | `true` | `429` (unverified) | `You've hit your session limit · resets 3:45pm` / `You've hit your weekly limit · resets Mon 12:00am` / `Credit balance is too low` / `spend limit reached (…)` (documented) | **No** | Fail the job with the reset time in the log. Tomorrow's cron picks it up. Distinguished from #1 by the words "limit" / "resets" / "balance" versus "authenticate" / "expired" / "Invalid" / "OAuth". |
| 3 | **CLI_HANG** | `124` from `timeout` (`143` if the CLI is SIGTERM'd directly) | — | — | file empty or truncated | **Yes**, ×3 | Normal run is ~110 s with ~89 s of silent time-to-first-token — don't set the timeout near that. 600 s is 5.5x headroom. |
| 4 | **MALFORMED_OUTPUT** | 0 or 1 | `false` or `true` | `null` | valid envelope, but `structured_output` missing / `scores` empty / id set doesn't match input | **Yes**, ×3 | Includes the `subtype: "error_max_turns"` case from trap 3. The id-set check is the only thing that catches a *short* result — the schema won't. |
| 5 | *(transient, folds into #3/#4)* | 1 | `true` | `429` / `529` | `API Error: Request rejected (429)…` / `Repeated 529 Overloaded errors` (documented) | **Yes** | The CLI already retries these internally with backoff; the outer loop is the backstop. 529 does not count against quota. |

Boundary between #1 and #2, since the ticket asks specifically: both are exit 1 with `is_error: true`
and a populated `result`. **`api_error_status` separates them structurally** — 401 for auth, 429 for
limits — and the `result` wording separates them textually. Match on `api_error_status` first and use
the text only as a fallback, because wording changes across releases and status codes don't.

Two things left **unverified**, flagged rather than guessed:

- The exact `api_error_status` on subscription usage-limit exhaustion. 429 is what the documented
  behaviour implies (spend caps are described as "a `429` marked `x-should-retry: false`"), but a real
  exhausted limit could not be triggered on demand. The `result`-text match in the snippet covers it
  either way; if a real exhaustion ever hits, capture the envelope and pin this down.
- Whether `--json-schema` validation failure surfaces distinctly from a plain malformed result. Every
  measured run either validated or failed for another reason. Treated as #4.

### One more probe worth adding later

The sentinel workflow in the old repo is a good idea that costs nothing: a separate job, running a
couple of hours after the daily one, that fails loudly if the expected output file for today doesn't
exist. It catches the class this taxonomy can't — the run that never started, or died so early it
logged nothing. That belongs to the loop-breaks ticket, not this one, but it's the cheapest possible
version of "did the loop actually run".

---

## Sources

Primary docs (all fetched 2026-08-24):

- [Run Claude Code programmatically (headless)](https://code.claude.com/docs/en/headless) — `-p` flags, `--json-schema` / `structured_output`, exit codes, SIGTERM/143, bare mode, `api_retry` event enum, 10 MB stdin cap
- [Authentication](https://code.claude.com/docs/en/authentication) — `claude setup-token`, one-year lifetime, `CLAUDE_CODE_OAUTH_TOKEN`, credential precedence, bare mode exclusion
- [Error messages](https://code.claude.com/docs/en/errors) — usage-limit, auth, 429 and 529 message text
- [GitHub Actions](https://code.claude.com/docs/en/github-actions) — `claude-code-action@v1`, secret naming, OAuth token = subscription not API billing, per-subscriber token scope

Prior art:

- `neoyipeng2018/my_life`, `.github/workflows/research-tape-{daily,skills,sentinel}.yml` — the probe pattern, `timeout` wrapping, autoupdater env vars
- `neoyipeng2018/my_life`, `ai-finance-trends-landing/src/lib/server/{claude-cli,judge}.ts` — the spawn helper, 180 s default timeout, 3-attempt linear backoff, envelope-walking parser, id-set assertion, and the `--tools ""` no-op bug

Measured directly against `claude` v2.1.241 with 60 real arXiv `q-fin.{CP,TR,PM}` abstracts: token
cost per candidate, prompt overhead with and without `--system-prompt`, tool counts under `--tools ""`
and `--strict-mcp-config`, the `--max-turns 1` failure, the auth-failure envelope, and the 110 s
60-candidate wall clock.
