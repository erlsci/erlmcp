# Milestone M2b: Resources, prompts, logging, completion & conformance

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** the remaining server feature surface — resources (incl. templates +
subscriptions), prompts, logging, completion, pagination across those endpoints —
plus a resource/prompt example and the server conformance scorecard. M2b is the
second half of the former M2; it builds on **M2a** (tools, ergonomics,
discoverability) and reuses its schema/validation, pagination, and `list_changed`
patterns.

**Locked decisions (carried):** JSON via `erlmcp_codec`; validator = `jesse` at
the edge; OTP 25+; coverage 90% scoped; validate at the edge, crash in the
interior; no shared records; no `_new` forks; no macros for logic.

**Branch:** `task/0.6.0-m2b`, cut from `release/0.6.x`; PR into `release/0.6.x`.
**Depends on M2a landing first.** All Verify commands run from the repo root. All
rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M2b-1 | `resources/list` (paginated) + `resources/read` return registered resources and their contents. | CT: list + read round-trip; pagination round-trips with an opaque cursor. | serious | dev plan M2b; Phase 2 | open | | |
| M2b-2 | Resource templates: `resources/templates/list` + templated `resources/read` (RFC 6570 URI-template expansion). | CT: a template lists and reads with parameters. | serious | dev plan M2b | open | | |
| M2b-3 | `resources/subscribe` + `resources/unsubscribe`; `notifications/resources/updated` fires on a subscribed resource change. | CT: subscribe → mutate → `updated` observed; after unsubscribe → silence. | correctness | dev plan M2b | open | | |
| M2b-4 | `notifications/resources/list_changed` on runtime resource add/remove. | CT: add/remove → notification observed. | correctness | dev plan M2b | open | | Reuses the M2a-10 `list_changed` pattern. |
| M2b-5 | `prompts/list` (paginated) + `prompts/get` (with arguments) return prompt definitions and rendered messages. | CT: list + get-with-args round-trip. | serious | dev plan M2b | open | | |
| M2b-6 | `notifications/prompts/list_changed` on runtime prompt add/remove. | CT: add/remove → notification observed. | correctness | dev plan M2b | open | | |
| M2b-7 | `logging/setLevel` + `notifications/message`: setting the level changes which log notifications are emitted. | CT: set level; messages below threshold suppressed, at/above emitted. | serious | dev plan M2b — make advertised logging real | open | | The audit found logging advertised but not implemented. |
| M2b-8 | `completion/complete` returns completions for prompt arguments and resource-template parameters. | CT: a completion request returns candidate values. | correctness | dev plan M2b | open | | |
| M2b-9 | Cursor/nextCursor pagination is consistent across `resources/list`, `resources/templates/list`, and `prompts/list` (opaque cursor, stable ordering). | CT: each endpoint paginates correctly; cursor opaque + ordering stable. | correctness | dev plan M2b (pagination across all list endpoints) | open | | Mirrors `tools/list` pagination (M2a-4). |
| M2b-10 | The advertised capability map includes `resources` (+`subscribe`/`listChanged`), `prompts` (+`listChanged`), `logging`, and `completions` only when registered/supported. | CT: capability map matches registrations. | correctness | dev plan M2b; Phase 2 §8 | open | | Extends M2a-12. |
| M2b-11 | A resource+prompt example server (e.g. weather with resources) exercises resources, templates, subscriptions, prompts, and completion end to end. | CT `erlmcp_example_weather_SUITE` drives those surfaces green. | serious | dev plan M2b DoD | open | | The resources half of the non-trivial example. |
| M2b-12 | `erlmcp_conformance` covers the M2 server surface (L0–L4 server scenarios) and reports a server score ≥ rmcp's reference (87.5%). | The harness runs the server scenarios and emits a server score ≥ 87.5%. | serious | dev plan M2 DoD ("conformance server score ≥ rmcp"); Phase 2 §9 | open | | Harness grown incrementally; the **formal/published** scorecard is **M5** (dev plan §3). M2b lands the server scenarios + score. |
| M2b-13 | M2b-implemented modules are removed from `cover_excl_mods`; the gate holds ≥90% over them. | `cover_excl_mods` no longer lists the M2b modules; CI `cover --min_coverage=90` passes including them. | serious | coverage ratchet | open | | |
| M2b-14 | Dialyzer clean; CI green on `task/0.6.0-m2b`. | `rebar3 dialyzer` exit 0; CI (compile+xref+eunit+CT+proper+dialyzer+cover) green on the branch. | serious | dev plan M2b DoD | open | | |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
server feature surface. `correctness` = a guarantee the feature claims. `polish`
= hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M3+

_(Filled in at close — e.g. client-side counterparts deferred to M3, anything the
conformance harness still lacks for M5.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 14. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
