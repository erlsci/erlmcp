# Milestone M4: Transports

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** production transports behind the one `erlmcp_transport` behaviour, with a
unified transport↔session contract so the session is genuinely transport-agnostic.
The same example server runs unchanged over stdio, TCP, and streamable HTTP. M4 also
absorbs the registry + supervision-tree coverage re-homed here at the M2b close (so
that work, tagged `% M4` in `cover_excl_mods`, finally lands in a ledger).

**Locked decisions (carried + transport-specific):**
- JSON via `erlmcp_codec`; `jesse` at the edge; OTP 25+; coverage 90% scoped
  (exclusion list shrinks — M4-11/12/13); validate at the edge, crash in the
  interior; no shared records; no `_new` forks; no macros for logic.
- **Harvest, don't reinvent** (`phase5-prior-art-reconciliation.md` §5; Phase 2 §6):
  the `erlmcp_transport` behaviour, `validate_transport_config/1`, the per-transport +
  behaviour-conformance test-suite layout, and `start_{stdio,tcp,http}_setup`
  convenience functions come from the July-2025 prior art.
- **`erlmcp_transport_http` is the reference pattern** (gen_server, monitored `owner`,
  pid-based `send/2`, owner-direct delivery; deadlock fixed in 57e2f50). Bring stdio
  and tcp **up to** this shape — **do not revert http.** Its meck-mocked suite
  (`erlmcp_transport_http_tests.erl`) is the per-transport template.
- **Transports talk to the bound session directly** (no registry hot-path routing —
  the M1-13 invariant).

**Branch:** `task/0.6.0-m4`, cut from `release/0.6.x` (after M3a/M3b land); PR into
`release/0.6.x`. Depends on M1 (transport behaviour + session spine) and M2 (a server
to run). All Verify commands run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M4-1 | One transport↔session contract: every transport delivers inbound to its bound session by the **same** mechanism + tag, and the session consumes it identically; outbound goes through the behaviour `send/2`. The current divergence (`{transport_data}` via cast vs `Session ! {transport_data}` vs `Owner ! {transport_message}`) is reconciled. | `grep -rn "transport_message\|transport_data" src` shows one inbound tag used uniformly by all transports + both sessions; CT: a session receives inbound identically regardless of transport. | serious | dev plan M4; Phase 2 §6; M1-12/M1-13 | open | | The session must stay transport-agnostic. Pick one tag + one mechanism and apply everywhere. |
| M4-2 | `validate_transport_config/1` validates each transport's config map at the edge (stdio/tcp/http/streamable_http); invalid config is rejected before a transport starts. | EUnit: valid configs accepted; each transport's invalid/missing-key config rejected with a clear error. | serious | dev plan M4; prior art §5 (validate-at-edge) | open | | Map-based validated config; no booleans-as-flags. |
| M4-3 | `erlmcp_transport_stdio` conforms to the `erlmcp_transport` behaviour in the http reference shape (pid-based, session-direct delivery), leaves `cover_excl_mods`, and holds ≥90%. | `cover_excl_mods` no longer lists `erlmcp_transport_stdio`; CT stdio per-transport suite passes; cover gate passes including it. | serious | dev plan M4 (stdio → reference shape) | open | | M1-12 rewrote it; M4 conforms + covers it. |
| M4-4 | `erlmcp_transport_tcp` conforms to the behaviour in the reference shape, leaves `cover_excl_mods`, and holds ≥90%. | `cover_excl_mods` no longer lists `erlmcp_transport_tcp`; CT tcp per-transport suite passes; cover gate passes including it. | serious | dev plan M4 | open | | ~327 LOC already; conform + cover. |
| M4-5 | `erlmcp_transport_http` (HTTP + SSE) conforms to the behaviour, including SSE inbound delivery; remains the reference (not reverted). | CT: http per-transport suite passes incl. an SSE inbound path; behaviour-conformance suite (M4-8) passes for http. | serious | dev plan M4 (HTTP + SSE) | open | | Already pid-based + covered; add/confirm SSE inbound. |
| M4-6 | `erlmcp_transport_streamable_http` (current-spec streamable HTTP transport) is implemented to the behaviour, leaves `cover_excl_mods`, and holds ≥90%. | `cover_excl_mods` no longer lists `erlmcp_transport_streamable_http`; CT suite passes; cover gate passes including it. | serious | dev plan M4 (current-spec HTTP transport) | open | | Currently a ~33-LOC stub. |
| M4-7 | Convenience setup functions `start_stdio_setup/2`, `start_tcp_setup/3`, `start_http_setup/3` (+ streamable) wire transport↔session ergonomically via the facade. | CT: each setup function starts a working transport bound to a session; a request round-trips. | correctness | dev plan M4; prior art §5 | open | | Ergonomics preserved from prior art; thin wrappers, no logic. |
| M4-8 | A behaviour-conformance test suite drives **every** transport through the `erlmcp_transport` contract (`init/2`, `send/2`, `close/1`, optional `get_info/1`). | CT `erlmcp_transport_conformance_SUITE` runs the same contract checks against stdio/tcp/http/streamable_http; all pass. | serious | dev plan M4; prior art §5 (behaviour-conformance suite) | open | | One suite, parameterized over transports — the "one behaviour" proof. |
| M4-9 | The same example server runs **unchanged** over stdio, TCP, and streamable HTTP. | CT: one example server module is started over each transport in turn; an identical request/response exchange succeeds on all three. | serious | dev plan M4 DoD | open | | The headline DoD: transport-agnostic session proven. |
| M4-10 | Transport-level conformance scenarios are added to `erlmcp_conformance` and pass. | The harness's transport scenarios run and pass for each transport. | correctness | dev plan M4; Phase 2 §9 | open | | Formal scorecard remains M5; M4 lands the transport scenarios. |
| M4-11 | `erlmcp_registry` (discovery-only, no hot-path routing) gains tests, leaves `cover_excl_mods`, and holds ≥90%. | `cover_excl_mods` no longer lists `erlmcp_registry`; CT/EUnit registry suite passes; cover gate passes including it. | serious | M2b close re-home (`% M4`); M1-13 | open | | Coverage that fell through M1/M2; finally landed. Confirm M1-13's "no per-message routing" still holds under test. |
| M4-12 | The supervision tree gains tests and leaves `cover_excl_mods`: `erlmcp_app`, `erlmcp_sup`, `erlmcp_server_sup`, `erlmcp_session_sup`, `erlmcp_transport_sup`; gate ≥90% over them. | `cover_excl_mods` no longer lists those five; CT exercises startup/restart; cover gate passes including them. | serious | M2b close re-home (`% M4`); coverage ratchet | open | | After M4, only `erlmcp_task`/`erlmcp_task_sup` (M6) remain excluded. |
| M4-13 | Dialyzer clean; CI green on `task/0.6.0-m4`. | `rebar3 dialyzer` exit 0; CI (compile+xref+eunit+CT+proper+dialyzer+cover) green on the branch. | serious | dev plan M4 DoD | open | | |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
transport layer or the "one behaviour, transport-agnostic session" goal.
`correctness` = a guarantee the feature claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M5+

_(Filled in at close — e.g. the behaviour-conformance suite feeding M5's scorecard;
whether M3b-10's cross-node test should migrate onto a real M4 transport; any module
still in `cover_excl_mods`.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 13. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
