# Milestone M3a: Client request API

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** a symmetric client — `erlmcp_client_session` consumes the full M2 server
surface (tools, resources, prompts, logging, completion) with pagination, progress
receipt, cancellation issuance, and notification handling. M3a is the first half of
the former M3; **M3b** adds the server→client features (sampling, roots,
elicitation) and the bidirectional request machinery.

**Locked decisions (carried):** JSON = `jsx` behind `erlmcp_codec`; validator =
`jesse`, wired at the boundary; OTP 25+; coverage 90% scoped (exclusion list shrinks
— M3a-13); validate at the edge, crash in the interior; no shared records; no `_new`
forks; no macros for logic. **Reuse, don't reinvent:** the M1 `client_session` spine
(`pending` correlation map, `next_id`, `send_request/4`), and the M2 server's
opaque-cursor pagination shape and `list_changed` notifications.

**Branch:** `task/0.6.0-m3a`, cut from `release/0.6.x`; PR into `release/0.6.x`.
Depends on M1 (client_session spine) and M2a/M2b (the server surface consumed). All
Verify commands run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M3a-1 | `erlmcp_client_session` issues `tools/list` (consuming cursor/nextCursor) and `tools/call`, correlating each response to its caller via the M1 `pending` map. | CT: client calls `tools/list` against an M2 server and receives the tool set; `tools/call` returns the handler result to the caller. | serious | dev plan M3a; Phase 2 §3,§7 | open | | Reuses M1 correlation; no new concurrency machinery. |
| M3a-2 | Client issues `resources/list` and `resources/read`. | CT: list returns the registered resources; read returns contents for a known URI. | serious | dev plan M3a | open | | |
| M3a-3 | Client issues `resources/templates/list` and a templated `resources/read`. | CT: templates listed; a templated read resolves and returns contents. | correctness | dev plan M3a | open | | Mirrors M2b-2 server side. |
| M3a-4 | Client issues `resources/subscribe`/`unsubscribe` and handles inbound `notifications/resources/updated` (delivered to the caller/owner). | CT: subscribe → server emits `updated` → client observes it; unsubscribe stops delivery. | serious | dev plan M3a; Phase 2 §3 | open | | |
| M3a-5 | Client issues `prompts/list` and `prompts/get` (with arguments). | CT: list returns prompts; get with arguments returns the rendered messages. | serious | dev plan M3a | open | | |
| M3a-6 | Client issues `logging/setLevel` and handles inbound `notifications/message`. | CT: setLevel acknowledged; a server log notification is delivered to the client owner. | correctness | dev plan M3a | open | | |
| M3a-7 | Client issues `completion/complete` for a prompt arg / resource-template param. | CT: completion request returns candidate values. | correctness | dev plan M3a | open | | |
| M3a-8 | Inbound `notifications/progress` is delivered to the caller of the originating request, keyed by its `progressToken`. | CT: a long-running server tool reports progress; the client caller observes `notifications/progress` for its token. | correctness | dev plan M3a; Phase 2 §3 (consumes M1-8/M2a-11) | open | | Receipt side of M2a-11. |
| M3a-9 | The client issues cancellation: `cancel/2` sends `notifications/cancelled` for an in-flight request id, and no late result is delivered to the caller. | CT: issue a request, cancel it, assert the caller gets a cancellation (not a stale result). | serious | dev plan M3a; Phase 2 §3; extends M1-6 | open | | M1 built `cancel/2` core; M3a confirms the no-late-result guarantee on the client side. |
| M3a-10 | The client handles `notifications/tools/list_changed`, `resources/list_changed`, and `prompts/list_changed` (surfaced to the owner so it can re-list). | CT: server runtime add/remove → client observes the matching `list_changed`. | correctness | dev plan M3a | open | | Receipt side of M2a-10 / M2b-4 / M2b-6. |
| M3a-11 | Client-side pagination consumption is consistent across `tools/list`/`resources/list`/`resources/templates/list`/`prompts/list`: a paginated server response is followed via `nextCursor` (opaque) until exhausted. | CT: a server list longer than one page is fully retrieved by the client following cursors; the cursor is treated as opaque. | serious | dev plan M3a; reuses M2a-4/M2b-9 | open | | One way to paginate, shared with the server's cursor shape. |
| M3a-12 | The client only invokes endpoints the server advertised at `initialize`; calling an unadvertised capability fails fast client-side (no malformed request sent). | CT: against a server with no prompts capability, a client `prompts/list` is rejected locally before transmission. | correctness | dev plan M3a; Phase 2 §8 | open | | Capability gating from negotiated `server_capabilities`. |
| M3a-13 | Legacy `erlmcp_client` is removed; `erlmcp_client_session` is the only client. `erlmcp_client` leaves `cover_excl_mods`; `erlmcp_client_session` holds the gate ≥90%. | `! ls src/erlmcp_client.erl 2>/dev/null`; `cover_excl_mods` no longer lists `erlmcp_client`; CI `cover --min_coverage=90` passes including `erlmcp_client_session`. | serious | M1 carry-forward (erlmcp_client → M3); "one way to do a thing" | open | | Closes the M1 deferral of the legacy client. |
| M3a-14 | A client example exercises the full request API end to end against an M2 server, with a CT suite. | CT `erlmcp_example_client_SUITE` drives list/read/call/get + subscribe + pagination + progress + cancellation green. | serious | dev plan M3a DoD | open | | The non-trivial example required by the DoD (client request half). |
| M3a-15 | Dialyzer clean; CI green on `task/0.6.0-m3a`. | `rebar3 dialyzer` exit 0; CI (compile+xref+eunit+CT+proper+dialyzer+cover) green on the branch. | serious | dev plan M3a DoD | open | | |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
client core. `correctness` = a guarantee the feature claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M3b+

_(Filled in at close — e.g. the bidirectional-request plumbing M3b needs, modules
still in `cover_excl_mods`, patterns M3b should reuse.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 15. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
