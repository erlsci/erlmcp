# Phase 6, Milestone P6-M3: Discoverability enhancement (library machinery)

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state — running each Verify command and reading diffs, not
> summaries. No milestone advances until the ledger is fully closed.

**Goal (Phase 6 §6, P6-M3):** make the existing discoverability layer
**README-grade on first contact**. The spec-blessed slot
(`InitializeResult.instructions`) is already populated (session L328/338) but
emits a thin "Categories: X. Use tools/list." stub; the rich per-tool semantics
(`when_to_use`/`next`) live one tool-call deep instead of at the handshake. This
milestone is **library machinery only** — enrich the generator, add a
server-identity block to the `directory` tool's output, promote the buried
"(exercises sampling)" notes to a first-class `protocol_features` field, and
tighten `directory`'s own description. The *example content* (servers supplying
the new identity/`protocol_features` values + READMEs) lands in **P6-M6**; the
*teaching* (a "make your server discoverable" howto section) lands in **P6-M7**.

Source: `docs/0.6.0/planning/phase6-discoverability-plan.md` (the plan,
reconciled with server-side state by CDC) and
`workbench/erlmcp-discoverability-assessment.md` (CD's consumer-side findings).

**Precondition / parallel (CD owns, not a ledger row):** CD verifies whether
Claude Desktop actually surfaces `InitializeResult.instructions` to the model.
If **yes**, enriching `instructions` is the highest-leverage change. If **no**,
leverage shifts onto descriptions + `directory` — *but the machinery changes
below still apply unchanged*; only their consumer-side impact shifts. So this
gating check does not block CC's work; it sizes its eventual payoff.

**Locked decisions (carried):** JSON via `jsx` behind `erlmcp_codec` only; `jesse`
at the edge (not exercised here); min OTP 25+; coverage 90% per-module scoped via
`cover_excl_mods`; opaque types + accessors, no shared records; one way to do a
thing, no `_new` forks. **Never loosen a check to make it pass** (`CLAUDE.md`):
no suppressions, no widened specs, no skipped tests — escalate instead. Dialyzer
gated to OTP 27+ (`make dialyzer`); run on **27 and 28**.

**Branch:** `task/0.6.0-p6m3`, cut from `release/0.6.x` **after P6-M2 merges**.
PR back into `release/0.6.x`. All Verify commands run from the repo root. All
rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| P6M3-1 | `erlmcp_instructions:generate/_` accepts richer inputs — server identity (name, purpose, version, source URL) + per-tool `protocol_features` — and emits **README-grade** output: identity, category overview, entry points, **protocol features exercised** (sampling / tasks / progress), and an explicit pointer to the `directory` tool. Multi-line, useful — not the current single-sentence stub. | EUnit `erlmcp_instructions_tests`: generate over a configured server returns a string that contains (a) the server name, (b) the configured purpose, (c) "directory" as the orientation pointer, (d) a "protocol features" line for tools that declare them. | serious | discoverability plan §2A | open | | The current generator emits "This server provides tools organized by category. Categories: arithmetic, demo. Start with: add. Use tools/list for the full catalog." — confirmed by reading `erlmcp_instructions.erl`. This row replaces that with README-grade output. |
| P6M3-2 | **Author-supplied override** is honored: if the server config provides `instructions` (a binary), it is used verbatim instead of auto-generation. | EUnit: starting a server with `#{instructions => <<"…custom README…">>}` causes `initialize` to return that exact binary in the `<<"instructions">>` field. | serious | discoverability plan §2A | open | | Auto-generation is the smart default; the override gives authors full control when they want a hand-written SKILL.md-style document. |
| P6M3-3 | The `initialize` response carries the enriched `instructions` end-to-end (no regression in delivery). | CT `erlmcp_server_session_SUITE`: an initialize over a configured server returns an `InitializeResult` whose `<<"instructions">>` matches `erlmcp_instructions:generate/_` for that server. | correctness | discoverability plan §2A | open | | Guards against an enrichment landing in the generator but not reaching the wire. |
| P6M3-4 | The `directory` tool's output includes a top-level **server identity block** with: `name`, `purpose`, `version`, `source`, `protocol_features`, `docs` (optional URL). | CT exercising the `directory` tool asserts the presence of the server block with these keys (when supplied by the configured server). | serious | discoverability plan §2B | open | | Today `directory` answers "what tools," not "what *is* this server." The block makes the second-contact surface a true README. |
| P6M3-5 | **`protocol_features`** is a first-class field on tool / resource / prompt specs (accepted at registration, type-validated when present, surfaced in `tools/list` `_meta`, and reflected in `directory` output + the instructions string). | `erlmcp_server`'s registration validators accept `protocol_features => [atom()]` (validate-at-edge); CT registers a tool with `protocol_features => [sampling]` and asserts it appears in `tools/list` `_meta`, in `directory` output, and in the instructions string. | serious | discoverability plan §2C | open | | Promotes the buried "(exercises sampling)" notes from `when_to_use` prose into a structured, prominent field — so a consuming LLM is warned *before* it calls `explain`/`slow_compute` blind. |
| P6M3-6 | The `directory` tool's own **description** starts with unmissable orientation language (e.g. "Start here — an oriented overview of this server, with workflow hints and which tools use advanced protocol features"). | `grep -q "Start here" src/erlmcp.erl` (in `make_directory_tool/0`); the description appears verbatim in `tools/list` output. | correctness | discoverability plan §2D | open | | Makes `directory`'s orientation role visible to clients that surface only descriptions. |
| P6M3-7 | **Quick-win**: the auto-generated `instructions` points users to the **`directory`** tool, not `tools/list`. | EUnit: the generated string contains the substring "directory" (case-insensitive). | correctness | discoverability plan §1 (free quick win) | open | | Today it says "Use tools/list" — flipping the pointer is a one-line, high-value change independent of the rest of the enrichment. |
| P6M3-8 | **No regression**: all M1/M2 tests still pass; `make check` exits 0. | `make check` green; `rebar3 eunit` + `rebar3 ct` 0 failures. | serious | DoD | open | | |
| P6M3-9 | **Coverage** — `erlmcp_instructions` and the directory-tool helpers in `erlmcp.erl` each ≥90% per-module; `cover_excl_mods` scoping retained (no *new* exclusions). | `rebar3 as test cover -v --min_coverage=90` exits 0; per-module figures for `erlmcp_instructions` and `erlmcp` ≥90%. | serious | Locked decision (coverage) | open | | Pre-spec the scoping in the first commit — M1's coverage-churn lesson. |
| P6M3-10 | **Dialyzer clean** on OTP 27 **and** 28 under the strict set, **no suppressions**, no widened specs. | `make dialyzer` clean on 27 and 28; `! grep -rn "nowarn\|-dialyzer(" src` (no new suppressions). | serious | DoD; `CLAUDE.md` never-loosen rule | open | | |
| P6M3-11 | **CI green** on `task/0.6.0-p6m3` across the OTP 25–28 matrix. | CI workflow (compile + xref + examples + eunit + CT + proper + dialyzer[27/28] + cover) passes on the branch. | serious | DoD | open | | CI is the independent reproducer. |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
milestone. `correctness` = a guarantee P6-M3 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to P6-M4+

_(Filled in at close — e.g. example servers supplying real `purpose`/`source`/
`protocol_features` values (P6-M6); a "make your server discoverable" section in
the howto (P6-M7). Note any module still in `cover_excl_mods` with its re-entry
milestone.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 11. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
