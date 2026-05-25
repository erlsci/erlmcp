# Phase 6, Milestone P6-M1: Core spine (server/session split + responder)

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state — running each Verify command and reading diffs, not
> summaries. No milestone advances until the ledger is fully closed.

**Goal (Phase 6 §6, P6-M1):** stand up the transport-agnostic spine. Separate the
per-server **catalog** (`erlmcp_server`, ETS-backed) from the per-conversation
**session** (`erlmcp_server_session`); introduce the opaque **responder**
(`erlmcp_reply`) and route every outbound message through it; carry a per-request
reply target plus a session push channel; generalize `erlmcp_ctx` off the raw
transport pid; redefine the `erlmcp_transport` behaviour to the real
message/responder + lifecycle contract; make registration config-driven into the
server; and add the outbound UTF-8 well-formedness guard at the emit boundary. No
transport is fully wired end-to-end this milestone — that is P6-M2 (stdio). The
spine must be unit- and property-testable with a stub responder.

**Locked decisions (carried):** JSON = `jsx` behind `erlmcp_codec` only; schema
validator = `jesse`; minimum OTP 25+; coverage gate 90% scoped via
`cover_excl_mods`; validate at the edge, crash in the interior; opaque types, no
shared records across boundaries / in exported specs; one way to do a thing, no
`_new` forks.

**Branch:** `task/0.6.0-p6m1`, cut from `release/0.6.x`; PR into `release/0.6.x`.
All Verify commands run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| P6M1-1 | `erlmcp_server` exists and owns the catalog (tools/resources/prompts + capabilities + identity) in an ETS table it owns; entries are registered through it and read back. | `grep -qn "ets:new" src/erlmcp_server.erl`; EUnit `erlmcp_server_tests`: register tool/resource/prompt then read back returns them. | serious | Phase 6 §3.1 | open | | Process type (gen_server vs sup+ETS owner) is CC's call; the table is `protected`, owned by the server, read by sessions. |
| P6M1-2 | Catalog/conversation split: `erlmcp_server_session` no longer holds the catalog; it reads tools/resources/prompts from its `erlmcp_server` by reference. Two sessions of one server share one catalog. | CT `erlmcp_server_session_SUITE`: register a tool once on the server; **two** independent sessions each return it from `tools/list`; registering after a session exists is visible to it. Plus `! grep -nE "^\s+(tools|resources|prompts)\b\s*=" src/erlmcp_server_session.erl` (no catalog fields in session state). | serious | Phase 6 §1.1, §3.1–3.2 | open | | The headline anti-pattern removal. The behavioural CT is the primary evidence; the grep is the structural backstop. |
| P6M1-3 | `erlmcp_reply` is an opaque responder with `send/2`; the `{device, Pid}` kind routes to `Pid ! {send, Json}`. | `grep -qE "opaque\|export_type" src/erlmcp_reply.erl`; EUnit `erlmcp_reply_tests`: a device responder over a test pid delivers `{send, Json}`. | serious | Phase 6 §3.3 | open | | Only the `{device,_}` kind exists this milestone; `{http,_,_}`/`{sse,_}` arrive in P6-M3. |
| P6M1-4 | The session emits **exclusively** through `erlmcp_reply:send/2`; no direct `Transport ! {send, _}` (or `... ! {send, _}`) remains in the session. | `! grep -nE "!\s*\{send," src/erlmcp_server_session.erl`; CT: a response reaches the test responder. | serious | Phase 6 §1.2, §3.3 | open | | Closes the single-pid emit seam. |
| P6M1-5 | The session carries a **per-request reply target** through the async worker round-trip (each response returns to its originating request's responder) and a separate **session push channel** for unsolicited server→client messages. | CT: two concurrent requests with distinct stub responders each receive only their own response; a server-initiated notification is delivered to the push channel. | serious | Phase 6 §3.3 | open | | This is what makes HTTP response-correlation possible later; stdio collapses both to one device responder. |
| P6M1-6 | `erlmcp_ctx` no longer carries a raw transport pid; progress and peer requests route through the session. | `! grep -n "transport" src/erlmcp_ctx.erl`; EUnit/CT: `report_progress/3` still emits `notifications/progress`; `request_peer/3` still round-trips. | correctness | Phase 6 §1.2, §3.3 | open | | The `ctx.transport` field was vestigial; removing it prevents a second stdio-shaped coupling. |
| P6M1-7 | `erlmcp_transport` behaviour is redefined to the real contract: lifecycle (`init`/`serve`/`close`) + inbound delivery of a framed message **with its responder** + outbound via the responder. The old `send(state(), iodata())` callback is gone. | `grep -qn "serve" src/erlmcp_transport.erl` (lifecycle callback present); `! grep -n "send(state()" src/erlmcp_transport.erl`; `grep -c "^-callback" src/erlmcp_transport.erl` ≥ 3. | serious | Phase 6 §3.4 | open | | The behaviour now matches how transports are actually driven. |
| P6M1-8 | Registration is config-driven: `erlmcp_server` accepts `tools`/`resources`/`prompts`/`handler` in its start config and registers them during its own **synchronous** start, before it can be served. | EUnit: a server started with a populated config exposes the full catalog immediately, with **no** post-start registration call. | serious | Phase 6 §3.6, §1.4 | open | | The structural foundation for closing the startup race in P6-M2 (catalog built before `serve`). |
| P6M1-9 | Outbound UTF-8 well-formedness guard at the emit/codec boundary: an outbound payload containing an ill-formed binary **fails closed** (not emitted) rather than shipping invalid bytes. | EUnit `erlmcp_codec_tests` (or emit-boundary test): encoding a term carrying an ill-formed binary (e.g. `<<16#95>>`) is rejected/raises at the boundary; a correct `/utf8` payload passes. | serious | Phase 6 §2; handoff §2.3 | open | | jesse cannot catch this (it validates the decoded term); a custom check is required. Full schema validation is P6-M4. |
| P6M1-10 | The dead `initializing` state is removed; session states are `uninitialized → operational → shutting_down`. | `! grep -n "initializing" src/erlmcp_server_session.erl`; CT: documented transitions hold (a non-`initialize` method before init is rejected). | correctness | Phase 6 §3.2 | open | | The `initializing` state was unreachable; dead state hides bugs. |
| P6M1-11 | No `jsx:` calls outside `erlmcp_codec` (the new emit/UTF-8 guard must not introduce one). | `! grep -rn "jsx:" src --include=*.erl \| grep -v erlmcp_codec.erl` → no matches. | serious | Locked decision | open | | |
| P6M1-12 | The new modules use opaque types; no shared records cross a module boundary or appear in an exported spec. | `grep -qE "opaque\|export_type" src/erlmcp_reply.erl src/erlmcp_server.erl`; `! grep -rn "^-record" include/ 2>/dev/null`. | serious | Locked decision; Phase 6 §3 | open | | Records may stay private to a module; never in `.hrl`, never in exported specs. |
| P6M1-13 | A PropEr property over responder routing / reply correlation passes (N requests with distinct responders → each response correlates to its own responder). | `rebar3 proper -c`: the new property (e.g. `prop_reply_correlation`) passes alongside the existing envelope/session properties. | correctness | Phase 6 §3.3; Phase 2 §9 | open | | Guards the per-request reply-target invariant under concurrency. |
| P6M1-14 | The P6-M1 modules are included in coverage (removed from `cover_excl_mods` where applicable) and the gate holds ≥90% over them. | `cover_excl_mods` does not exclude `erlmcp_server`, `erlmcp_reply`, `erlmcp_server_session`, `erlmcp_ctx`; `rebar3 as test cover -v --min_coverage=90` passes. | serious | Locked decision (coverage) | open | | Per-module floor — a strong module may not carry a weak one over the aggregate line. |
| P6M1-15 | Dialyzer is clean. | `rebar3 dialyzer` exits 0 with no warnings. | serious | DoD | open | | The opaque responder + server API put real specs under analysis. |
| P6M1-16 | Compile is warning-free (`warnings_as_errors`) and `xref` is clean. | `rebar3 compile` exits 0 with no warnings; `rebar3 xref` reports no issues. | serious | DoD; CLAUDE.md before-submitting | open | | Removing the catalog from the session will surface dangling references — fix, don't suppress. |
| P6M1-17 | CI is green on `task/0.6.0-p6m1` across the OTP 25–28 matrix. | The CI workflow (compile + xref + eunit + CT + proper + dialyzer + cover) passes on the branch. | serious | DoD | open | | CI is the independent reproducer; CDC's sandbox has no Erlang toolchain. |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
spine. `correctness` = a guarantee P6-M1 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to P6-M2+

_(Filled in at close — e.g. the per-server subtree + `serve/1` gate + stdio rebuild
(P6-M2); the `{http,_,_}`/`{sse,_}` responder kinds + session manager (P6-M3);
full outbound schema validation (P6-M4). Note any module still in `cover_excl_mods`
with its re-entry milestone.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 17. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
