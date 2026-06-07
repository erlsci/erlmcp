# Phase 6, Milestone P6-M6: Examples rehab + Claude Desktop acceptance

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state — running each Verify command and reading diffs, not
> summaries. No milestone advances until the ledger is fully closed.

**Goal (Phase 6 §6, P6-M6):** close the loop on the original "no tools available"
arc that started Phase 6. M3 built the **discoverability machinery** (identity
block, `protocol_features` field, enriched `instructions` generator, `directory`
tool); M5 built the **validation seam** (jesse inbound + outbound, the Icon /
taskSupport / UTF-8 regressions). M6 ships the **content** that flows through
both: each example server populates an identity block, declares
`protocol_features` on tools that exercise advanced protocol features, carries a
**user-manual-grade README** (model-facing, not just developer-facing), and is
verified end-to-end against **Claude Desktop** — the consumer the original bug
appeared in. This is library *application*, not library *machinery*.

This is the milestone where the consumer-side payoff of M3 + M5 becomes
**observable**: install any example in Claude Desktop, and the model sees a
useful identity block, a categorized tool list with `protocol_features`, and an
orientation pointer to the `directory` tool — without the developer having to
hand-write the `instructions` field.

**Locked decisions (carried):** JSON via `jsx` behind `erlmcp_codec` only;
`jesse` at the edge (M5 — exercised here by example payloads passing under it);
min OTP 25+; coverage 90% per-module scoped via `cover_excl_mods`; opaque types
+ accessors, no shared records; one way to do a thing, no `_new` forks.
**Never loosen a check to make it pass** (`CLAUDE.md`): no suppressions, no
widened specs, no skipped tests — escalate instead. Dialyzer gated to OTP 27+
(`make dialyzer`); run on **27 and 28**.

**Scope discipline:** **Do not modify the spine.** The unified
transport / session / responder seam (`erlmcp_server`, `erlmcp_server_session`,
`erlmcp_reply`, `erlmcp_codec`, the M3 `erlmcp_instructions` generator, the M5
`erlmcp_schema` validator) is **frozen for M6**. If an example needs a spine
feature that doesn't exist yet, **escalate** — that's a spine task, not an
example task. The point of M6 is to verify the M1–M5 spine carries the consumer
payload it was designed to carry; mutating it during M6 would undermine that
test. *Escalate-not-decide*; we have learned this twice in M5.

**Branch:** `task/0.6.0-p6m6`, cut from `release/0.6.x` **after P6-M5 merges**.
PR back into `release/0.6.x`. All Verify commands run from the repo root. All
rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| P6M6-1 | Each example server (`simple`, `calculator`, `weather`) populates an **identity block** in its `start/1` config: `name`, `purpose`, `version`, `source` (repo URL), optional `docs`. These flow into the M3 `directory` tool's server-identity block and into the auto-generated `instructions`. | `grep -nE "identity\s*=>" examples/*/src/*_server.erl` shows one match per example; CT `erlmcp_example_*_SUITE` asserts the `directory` tool's output carries the configured `name` + `purpose` for that server. | serious | Phase 6 §6 P6-M6; consumer-side payoff of P6M3-4 | open | | The values are real (point `source` at the actual GitHub URL, not a placeholder). The `purpose` line is what the model reads first. |
| P6M6-2 | Each tool that exercises an advanced MCP protocol feature declares it via `protocol_features` (the M3 field): calculator's `slow_compute` → `[tasks, progress]`; calculator's `explain` → `[sampling]`; weather's resource template → `[completion]` (or wherever the example genuinely demonstrates it). Tools that exercise nothing advanced (simple `echo`/`add`) declare no `protocol_features`. | `grep -nE "protocol_features\s*=>" examples/*/src/*_server.erl` shows the expected sites; CT asserts `tools/list` `_meta` carries `io.erlmcp/protocol_features` for the right tools. | serious | Phase 6 §6 P6-M6; consumer-side payoff of P6M3-5 | open | | Don't over-declare. A `[sampling]` claim is a *promise* the tool's handler actually uses sampling; an audit of one tool's handler should confirm the feature. |
| P6M6-3 | The **auto-generated `instructions`** for each example is README-grade out of the box (no author override) — it lists the server name + purpose, the category overview, the protocol features exercised, and the orientation pointer to `directory`. No example needs to supply an author override to read well. | CT `erlmcp_example_*_SUITE:instructions_readable` runs `initialize` on the configured server, asserts the returned `<<"instructions">>` binary contains: server name, server purpose, "directory" pointer, "protocol features" line listing the declared features. | serious | Phase 6 §6 P6-M6; consumer-side payoff of P6M3-1 / P6M3-7 | open | | The bet of M3 was that *machinery + content = no override needed*. M6 tests the bet. If an example *does* need an override to read well, that's a M3 machinery gap — escalate, don't paper over with a hand-written string. |
| P6M6-4 | Each example's **README** is rewritten for the **model-facing** reader (the LLM sees it via `instructions` / `directory` / linked docs), not just the developer reader. The dev-facing setup content (Claude Desktop config, run command, test commands) stays; the new content adds a one-paragraph **what this server is for** + **when to use which tool** that a model would find useful at first contact. | The README contains an "Identity" or "What this server is for" section matching the configured `purpose`; a "Tool orientation" section matching the `directory` tool's category structure. | correctness | discoverability plan / Phase 6 §6 | open | | The dev/model split: developer needs to *install* the server; the model needs to *use* it. The existing READMEs covered the first; M6 adds the second. |
| P6M6-5 | The original **payload-shape bugs** stay closed in the example tools: calculator's `emoji_icon/1` helper produces a P6M5-6-conformant Icon (`src` data-URI, no extra fields, `additionalProperties: false` honoured); calculator's `task_support` uses a P6M5-7-valid enum (`forbidden | optional | required`); no example tool registers `taskSupport => allowed` or the buggy `#{type=>emoji,emoji=>...}` shape. | `! grep -rnE "type\s*=>\s*emoji" examples/`; `! grep -rnE "taskSupport\s*=>\s*allowed\|task_support\s*=>\s*allowed" examples/`; CT exercising `tools/list` on each example passes M5's outbound validator with no `-32603`. | serious | handoff §1.3 / §1.5; closing the original arc | open | | This is the *example-side* mirror of P6M5-6/-7: M5 made the validator catch them; M6 ensures the examples don't *trip* them. The combination is the original bug *structurally cannot recur*. |
| P6M6-6 | `make compile-examples` is green; all three examples compile cleanly under their own rebar profiles with zero warnings (`warnings_as_errors` is on). | `make compile-examples` exits 0; output has no `Warning:` lines. | serious | DoD | open | | M2 added the target; M6 verifies it stays green after the M6 content changes. |
| P6M6-7 | **Claude Desktop acceptance test** — a hand-driven smoke test per example, with the procedure + observed state checked into `docs/0.6.0/acceptance/phase6-claude-desktop-acceptance.md`. For each example, the test confirms: (a) initialize succeeds; (b) the `instructions` field is surfaced (or, if CD doesn't surface it, the directory tool fills the gap); (c) `tools/list` returns the expected tools with `_meta` wayfinding; (d) the `directory` tool returns a clean orientation; (e) calculator's `slow_compute` produces progress notifications; (f) calculator's `explain` round-trips a sampling request back to the client. | The acceptance doc exists; each example has a section with the test procedure, the observed state (model output / screenshots / CD log captures as appropriate), and a **pass / partial / fail** verdict. Any "partial" or "fail" is closed by a documented follow-up issue, not a softpedal. | serious | Phase 6 §6 close; the original "no tools available" arc | open | | Hand-driven and one-shot — this is verification, not infrastructure. Cap the work to **one focused session** per example. If a defect is found, fix it on the spine *only if* trivial; otherwise file a follow-up and ship M6 with the defect documented. The pre-condition CD owns from M3 (does CD surface `instructions`?) is **answered here** — the answer drives which surfaces (`instructions` vs `directory`) carry the orientation. |
| P6M6-8 | **No regression** on M1–M5: every CT/eunit/PropEr suite from prior milestones still passes; the M5 inbound + outbound validators stay clean against the example payloads with no `-32600`/`-32602`/`-32603` from the wire except in tests that deliberately drive one. | `make check` exits 0; `grep -rnE "-32603\|invalid_payload" _build/test/logs/` shows only test-driven cases. | serious | DoD | open | | The architectural payoff verified: M3 + M5 + M6 stack cleanly on the M1/M2/M4 spine. |
| P6M6-9 | **Coverage** — example modules (`simple_server`, `calculator_server`, `weather_server`) each ≥90% per-module; the `cover_excl_mods` scoping retained (no *new* exclusions for examples). | `rebar3 as test cover -v --min_coverage=90` exits 0; per-module figures for the three example modules ≥90%. | serious | Locked decision (coverage) | open | | If a handler path is genuinely unreachable from CT (e.g. an `io:get_line` blocking loop, a guarded crash branch), close with a **named-ceiling amendment** listing the exact uncovered lines + per-line reason — the M2 stdio_sup / M4 http_sup pattern. *"We didn't write the test"* is **not** a ceiling. |
| P6M6-10 | **Dialyzer clean** on OTP 27 and 28 across the examples (their own rebar profiles), no suppressions, no widened specs. | `make compile-examples` then `rebar3 as <profile> dialyzer` for each example clean on 27 / 28; `! grep -rn "nowarn\|-dialyzer(" examples/` (no new suppressions). | serious | DoD; `CLAUDE.md` never-loosen rule | open | | Each example has its own rebar profile (M2). The dialyzer gate runs against each. |
| P6M6-11 | **CI green** on `task/0.6.0-p6m6` across the OTP 25–28 matrix. | CI workflow passes on the branch. | serious | DoD | open | | The independent reproducer; confirms 27 leg of dialyzer + cross-OTP compile of the example profiles. |
| P6M6-12 | **Ledger walk + closing report.** All 12 rows have a single valid final state (`done` / `deferred` / `no-op`; `done (amended criterion)` is fine) with grep/test-verifiable evidence. Closing tally arithmetically matches 12. Per-row dispositions; no prose summary. | The ledger has Status + Evidence on every row; the tally line at the bottom adds to 12. | serious | LEDGER_DISCIPLINE | open | | Recurring lesson: count the actual rows in the ledger file before declaring the walk complete. |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
milestone. `correctness` = a guarantee P6-M6 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to P6-M7

_(Filled in at close — e.g. any spine gap surfaced by P6M6-7 that needs to land
before the 0.6.0 tag, any documentation deltas the howto needs to absorb, any
example-side feature the user requested during acceptance that's a 0.7+ item.
Note any example module still in `cover_excl_mods` with its re-entry milestone.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 12. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
