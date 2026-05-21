# Milestone M1: The re-core (foundational architecture)

> Per-milestone verification ledger (see the project `LEDGER_DISCIPLINE.md`). CC
> works against this ledger; CDC verifies every disposition independently against
> the actual commit state. No milestone advances until the ledger is fully closed.

**Goal (dev plan M1):** a working stdio session that can initialize, ping,
negotiate version, and cancel — end to end — with nothing else. This is the
load-bearing milestone: per Phase 3 §6.2, cancellation, ping, and version
negotiation are all blocked behind the `gen_statem` session + per-request-process
spine. Build the spine once and those features become small.

**Locked decisions (carried from M0):** JSON = `jsx` behind `erlmcp_codec`; schema
validator = `jesse`; minimum OTP = 25+; coverage gate = 90% scoped to implemented
modules (the exclusion list shrinks this milestone — see M1-16). Validate at the
edge, crash in the interior (Phase 2 §5). One way to do a thing — no `_new` forks.

**Branch:** `task/0.6.0-m1`, cut from `release/0.6.x`; PR into `release/0.6.x`. All
Verify commands run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M1-1 | JSON access goes only through `erlmcp_codec`; no `jsx:` calls anywhere else. | `! grep -rn "jsx:" src --include=*.erl \| grep -v erlmcp_codec.erl` → no matches; EUnit `erlmcp_codec_tests` encode/decode round-trip. | serious | M0 carry-forward #3; Phase 2 §2; locked decision | open | | Codec boundary. Today `jsx:` appears in `erlmcp_json_rpc`, `erlmcp_stdio_server` — both re-seated/removed this milestone. |
| M1-2 | `erlmcp_json_rpc` encodes/decodes/classifies JSON-RPC 2.0 envelopes (request / response / notification / batch), with the full error-code set and graceful batch parsing. | EUnit `erlmcp_json_rpc_tests` covers each envelope kind + error codes (-32700/-32600/-32601/-32602/-32603); malformed batch degrades gracefully. PropEr `prop_envelope_roundtrip` (see M1-18). | serious | dev plan M1; Phase 2 §2 | open | | |
| M1-3 | `erlmcp_model` exposes opaque MCP types via constructors/accessors; no records cross a module boundary or appear in an exported spec. | `grep -qE "opaque\|export_type" src/erlmcp_model.erl`; `! grep -rn "^-record" include/ 2>/dev/null` (no shared records in includes); EUnit `erlmcp_model_tests` for constructors/accessors. | correctness | dev plan M1; Phase 2 §2 | open | | Records allowed *private* to a module; never in `.hrl`, never in exported specs. |
| M1-4 | `erlmcp_capabilities` builds the capability map from what the server actually registered, and negotiates the highest mutually-supported protocol version from a declared set. | EUnit `erlmcp_capabilities_tests`: highest common version chosen; disjoint sets rejected; unregistered features (e.g. no prompts) omitted from the advertised map. | serious | dev plan M1; Phase 2 §8; Phase 3 (A: version negotiation) | open | | Version negotiation is a first-class feature over a declared supported-version set, not a constant. |
| M1-5 | `erlmcp_server_session` is a `gen_statem` with states `uninitialized → initializing → operational → shutting_down`; method legality is gated by state + negotiated capabilities. | `grep -q "behaviour(gen_statem)" src/erlmcp_server_session.erl`; CT `erlmcp_server_session_SUITE`: a non-`initialize` method before initialization is rejected; documented state transitions hold. | serious | dev plan M1; Phase 2 §3; Phase 3 (C) | open | | |
| M1-6 | `erlmcp_client_session` is a `gen_statem` that drives `initialize` and can issue `ping` and cancellation via correlated round-trips. | `grep -q "behaviour(gen_statem)" src/erlmcp_client_session.erl`; covered by the e2e suite (M1-17). | serious | dev plan M1; Phase 2 §3,§7 | open | | M1 builds the client_session core needed for initialize→ping→cancel; the full client API (list/read/call/get, subscriptions) is **M3**. |
| M1-7 | The session runs one monitored worker process per in-flight request; a crashing handler is isolated — it becomes a `-32603` error response and the session survives — and a slow handler does not head-of-line-block other requests. | CT: a tool handler that crashes yields JSON-RPC `-32603` and `is_process_alive(Session)` stays true; a concurrent slow handler does not delay a second request. | serious | dev plan M1; Phase 2 §3,§5; Phase 3 (C); native-strength differentiator | open | | Per-request fault isolation — a headline BEAM win over rmcp. |
| M1-8 | `erlmcp_ctx` carries progress token, cancellation handle, `_meta`, and a peer handle; `report_progress/3` emits `notifications/progress` keyed by the request's `progressToken`. | EUnit/CT: `erlmcp_ctx` accessors; a worker calling `report_progress` produces a `notifications/progress` with the right token. | correctness | dev plan M1; Phase 2 §3 | open | | |
| M1-9 | Cancellation = worker termination: `notifications/cancelled` for an in-flight request terminates its worker; no late result is delivered; no token map is maintained. | CT: issue `notifications/cancelled`; the worker receives the kill (monitor `DOWN`); no result/late response is sent for that id. | serious | dev plan M1; Phase 2 §3; Phase 3 (A: cancellation); native-strength differentiator | open | | Cancellation-as-exit — the BEAM *is* the primitive. |
| M1-10 | `ping` round-trips, and concurrent requests are correctly correlated via the request-id table. | CT: `ping` returns its result; N concurrent requests each receive the response matching their id. | correctness | dev plan M1; Phase 3 (A: ping) | open | | |
| M1-11 | `erlmcp_transport` is a behaviour with the §6 callbacks: `init/2`, `send/2`, `close/1`, optional `get_info/1` + `handle_transport_call/2`. | `grep -c "^-callback" src/erlmcp_transport.erl` ≥ 3; `-optional_callbacks` lists the optional two. | serious | dev plan M1; Phase 2 §6; Phase 3 (C) | open | | Interface harvested from the July-2025 prior art (phase5 §5). |
| M1-12 | `erlmcp_transport_stdio` is a `gen_server` implementing `erlmcp_transport` that delivers inbound data **directly to its bound session**, with the `gen_server:call(self(), …)` deadlock fixed; framing uses iolists. | `! grep -rn "gen_server:call(self()" src`; CT: stdio transport delivers inbound to the session and the round-trip completes (no deadlock). | serious | dev plan M1; Phase 2 §6; Phase 3 (C; deadlock fix) | open | | `erlmcp_transport_http` (commit 57e2f50) is the reference pid-based pattern. |
| M1-13 | `erlmcp_registry` does discovery/binding only — no per-message routing on the hot path; once bound, the session talks to its transport and handlers directly. | `! grep -rn "route_to_server\|route_to_transport" src/erlmcp_registry.erl`; CT: a request/response exchange makes no per-message registry call. | serious | dev plan M1; Phase 2 §4; Phase 3 (C: registry hot-path) | open | | |
| M1-14 | The unique `_new` logic noted in M0-1 is re-seated onto the new core, or consciously dropped with rationale: registry-aware routing → session-direct (M1-13); `TransportId`-based init → `erlmcp_transport:init/2` (M1-11); async-cast send → transport `send/2`. | Each of the three items has a written disposition (re-seated location + covering test, or dropped + reason). | correctness | M0 carry-forward #1 (M0-1) | open | | Closes the M0-1 forward note. |
| M1-15 | `erlmcp_server.erl` and `erlmcp_stdio_server.erl` are removed; `erlmcp_server_session` is the only server implementation. | `! ls src/erlmcp_server.erl src/erlmcp_stdio_server.erl 2>/dev/null`; `ls src \| grep -i server` resolves to `erlmcp_server_session` (+ the sups). | serious | M0 carry-forward #2 (closes deferred **M0-2**); principle "one way to do a thing" | open | | Re-entry condition for M0-2 was "M1 `erlmcp_server_session` lands." |
| M1-16 | The M1-tagged modules are removed from `cover_excl_mods` as they are re-seated, and the gate holds ≥90% over them. | `cover_excl_mods` no longer lists `erlmcp_app`, `erlmcp_sup`, `erlmcp_server_sup`, `erlmcp_session_sup`, `erlmcp_transport_sup`, `erlmcp_server`, `erlmcp_json_rpc`, `erlmcp_registry`, `erlmcp_stdio`, `erlmcp_stdio_server`; CI `cover --min_coverage=90` passes with them included. | serious | M0 carry-forward #4; gives the coverage gate teeth | open | | `erlmcp`(M2a), `erlmcp_client`(M3), `erlmcp_transport_tcp`/`_stdio`(M4) stay excluded until their milestones. Skeletons leave as implemented. |
| M1-17 | A stdio client and server in the same VM complete `initialize → ping → cancel` end to end. | CT `erlmcp_e2e_SUITE` passes the initialize→ping→cancel scenario over the stdio transport. | serious | dev plan M1 DoD | open | | The milestone's headline acceptance scenario. |
| M1-18 | A PropEr model of the JSON-RPC envelope and the session lifecycle passes. | `rebar3 proper` (or the configured target): `prop_envelope_roundtrip` and `prop_session_lifecycle` pass. | serious | dev plan M1 DoD; Phase 2 §9 | open | | |
| M1-19 | Dialyzer is clean. | `rebar3 dialyzer` exits 0 with no warnings. | serious | dev plan M1 DoD | open | | First milestone with `-spec`-backed logic, so this now bites. |
| M1-20 | CI is green on `task/0.6.0-m1`. | The CI workflow (compile + xref + eunit + CT + proper + dialyzer + cover) passes on the branch. | serious | dev plan M1 DoD | open | | CI is the independent reproducer (CDC sandbox lacks the Erlang toolchain). |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
re-core. `correctness` = a guarantee M1 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M2+

_(Filled in at close — anything M1 hands forward, e.g. modules still in
`cover_excl_mods`, deferred client API → M3, transport work → M4.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 20. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
