# Milestone M6b: `_meta`, icons, batch & the 0.6.0 finish line

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** the three remaining protocol-completeness items — the `_meta` request/response
channel, tool `icons`, and session-level batch execution — plus the 0.6.0 coverage
endpoint (empty `cover_excl_mods`) and final release readiness. M6b is the second half
of the former M6; it **depends on M6a** (which empties the exclusion list down to the
task modules it implements).

**Locked decisions (carried):** JSON via `erlmcp_codec`; `jesse` at the edge; OTP 25+;
validate at the edge, crash in the interior; no shared records; no `_new` forks; no
macros for logic. **Per-module coverage policy (standing):** "we didn't write the test"
and "dead code" are not unreachability; a true ceiling needs line-level proof.

**Branch:** `task/0.6.0-m6b`, cut from `release/0.6.x` (after M6a lands); PR into
`release/0.6.x`. All Verify commands run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M6b-1 | The `_meta` channel works end to end: a request's `_meta` is carried through `erlmcp_ctx` to the handler, and a handler may set `_meta` on its response. | CT: a request with `_meta` → handler reads it via `erlmcp_ctx:meta/1` → the response carries the handler's `_meta`. | serious | dev plan M6b; M1-8 (`ctx` carries `_meta`) | open | | App-specific `_meta` passthrough, distinct from M2a's discoverability `_meta`. |
| M6b-2 | Tool `icons` are settable on the `add_tool` map and surfaced in `tools/list` (protocol-native `Icons`). | CT: a tool registered with `icons` shows them in `tools/list`. | correctness | dev plan M6b; 2025-11-25 `Tool extends … Icons` | open | | On the single `add_tool` map; not a parallel store. |
| M6b-3 | Session-level JSON-RPC **batch execution**: a batch of requests is dispatched (each via the per-request worker), responses aggregated into a batch array; an all-notification batch yields no response; malformed/partial batches degrade gracefully (per-member errors), session survives. | CT: a mixed request/notification batch round-trips with an aggregated response array; a batch with a malformed member yields a per-member error and the session stays alive. | serious | dev plan M6b; closes the M1-2 deferral (parse/classify landed; execution deferred) | open | | M1-2 built `decode_and_classify_any` + `encode_batch`; M6b wires session dispatch. |
| M6b-4 | `cover_excl_mods` is **empty** — every module in `src/` is in the coverage set — and the gate holds, with `erlmcp_transport_stdio`'s `io:get_line` reader loop the **sole** named line-level exception. | `cover_excl_mods` is `[]`; `rebar3 cover` passes at the gate; stdio is the only sub-90 module and its uncovered lines are named. | serious | coverage endpoint (M0 plan 90%→95% ratchet); standing per-module policy | open | | The capstone: 0.6.0 coverage is complete. |
| M6b-5 | The dated conformance scorecard is regenerated to include the `_meta`/icons/batch scenarios (and M6a's task scenarios). | The committed scorecard artifact includes the new scenarios; scores still ≥ rmcp reference. | correctness | dev plan M6b; M5a-1 artifact | open | | Keeps the published artifact honest with the final surface. |
| M6b-6 | Dialyzer clean; xref clean; full CI green on `task/0.6.0-m6b` — 0.6.0 release-ready. | `rebar3 dialyzer` exit 0; `rebar3 xref` clean; CI (compile+xref+eunit+CT+proper+dialyzer+cover) green. | serious | dev plan M6b DoD | open | | The 0.6.0 finish line. |

### Significance legend
`serious` = a DoD gate or coverage/anti-drift endpoint. `correctness` = a guarantee the
milestone claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M7 / post-0.6

_(Filled in at close — e.g. anything punted to the M7 stretch list.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 6. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
