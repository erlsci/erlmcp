# Milestone M3b: Server→client features (sampling, roots, elicitation)

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** the inverted-direction features. The server session can *initiate* a
request to its bound client and correlate the response; the client dispatches
*inbound* server requests to registered callback behaviours. With that bidirectional
plumbing, sampling works end-to-end and roots + elicitation work as client
callbacks. M3b is the second half of the former M3; it **depends on M3a** (the client
request spine) and on M2a/M2b (the server it answers to).

**Locked decisions (carried):** JSON = `jsx` behind `erlmcp_codec`; validator =
`jesse`, wired at the boundary; OTP 25+; coverage 90% scoped (exclusion list shrinks
— M3b-9); validate at the edge, crash in the interior; no shared records; no `_new`
forks; no macros for logic. **Reuse, don't reinvent:** the M1 correlation pattern
(`pending` map + `next_id`) — the server's outbound-request path mirrors the client's;
the `erlmcp_ctx` peer handle (M1-8) is the server-side initiation entry point; the
M2a-12 capability-derivation pattern, applied to the client side.

**Branch:** `task/0.6.0-m3b`, cut from `release/0.6.x` (after M3a is merged in); PR
into `release/0.6.x`. All Verify commands run from the repo root. All rows start
`open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M3b-1 | The **server session** can initiate a request to its bound client and correlate the response: it maintains an outbound `pending` map + id counter and a `request_peer/3`-style call usable from a tool worker via the `erlmcp_ctx` peer handle. | CT: a server-side caller issues a request to a stub client and receives the correlated response; a second concurrent outbound request is correlated independently. | serious | dev plan M3b; Phase 2 §3,§7; M1-8 peer handle | open | | The symmetric counterpart to M1's client→server correlation. One correlation pattern, both directions. |
| M3b-2 | The **client session** dispatches *inbound* server requests (not just responses) to registered callback modules; an unknown/unsupported method returns the correct JSON-RPC error, never crashing the session. | CT: an inbound request for a registered callback reaches it; an inbound request with no handler → `-32601` (method not found) and the session survives. | serious | dev plan M3b; Phase 2 §3,§5 | open | | Inbound-request path on the client; mirrors the server's dispatch + fault isolation. |
| M3b-3 | **Sampling end-to-end:** server issues `sampling/createMessage` to the client; the client runs its `erlmcp_sampling:handle_create_message/2` callback in a per-request worker and returns the result to the originating server worker. | CT: a server tool triggers `sampling/createMessage`; the registered client `erlmcp_sampling` handler runs and its result is delivered back server-side. | serious | dev plan M3b (A: full sampling); not just client-side dispatch | open | | The headline symmetry feature. Uses M3b-1 (server initiates) + M3b-2 (client dispatches). |
| M3b-4 | **Roots:** inbound `roots/list` → `erlmcp_roots:list_roots/1` callback returns the root list; the client can emit `notifications/roots/list_changed`. | CT: `roots/list` returns the callback's roots; a runtime change emits `roots/list_changed` observed server-side. | correctness | dev plan M3b (A: roots) | open | | |
| M3b-5 | **Elicitation:** inbound `elicitation/create` → `erlmcp_elicitation:handle_elicit/2` callback returns an accept/decline/cancel result with content. | CT: `elicitation/create` reaches the handler; accept returns content; decline/cancel return the correct shapes. | correctness | dev plan M3b (A: elicitation) | open | | |
| M3b-6 | Inbound server→client requests are validated at the **client boundary** (jesse / shape check) before dispatch; invalid params → `-32602` and the callback never runs. | CT: a malformed `sampling/createMessage` → `-32602`; the `erlmcp_sampling` handler is not invoked. | serious | dev plan M3b; Phase 2 §2,§5; validate-at-edge | open | | Mirror of M2a-6 on the client. |
| M3b-7 | The client advertises `sampling`/`roots`/`elicitation` in its `initialize` capabilities **only when** a corresponding handler is registered. | CT: with only a sampling handler registered, the client `initialize` advertises `sampling` and omits `roots`/`elicitation`. | correctness | dev plan M3b; Phase 2 §8; mirrors M2a-12 | open | | Derived from registrations, not hardcoded. |
| M3b-8 | A server+client example uses sampling + elicitation: the server requests both; the client provides handlers for them. | CT `erlmcp_example_sampling_SUITE` drives a sampling + elicitation exchange green. | serious | dev plan M3b DoD | open | | The non-trivial example required by the DoD (server→client half). |
| M3b-9 | `erlmcp_sampling`, `erlmcp_roots`, `erlmcp_elicitation` leave `cover_excl_mods`; the gate holds ≥90% over them. | `cover_excl_mods` no longer lists the three modules; CI `cover --min_coverage=90` passes including them. | serious | coverage ratchet; M2a-15/M1-16 pattern | open | | Skeletons enter coverage as implemented. |
| M3b-10 | Client and server in **separate nodes** complete a sampling + elicitation round-trip end to end. | CT `erlmcp_client_e2e_SUITE`: two Erlang nodes (or two OS processes over the stdio transport) complete the round-trip; no in-VM shortcut. | serious | dev plan M3b DoD | open | | See Notes on the transport question — distributed Erlang or stdio-between-nodes, **not** blocked on M4's TCP/HTTP. Raise an amendment if it genuinely needs M4. |
| M3b-11 | `erlmcp_conformance` **client** scenarios run and report a client score ≥ rmcp's reference. | The harness's client scenarios pass; reported client score ≥ the documented rmcp client reference. | serious | dev plan M3b DoD | open | | Grow the harness incrementally; the **formal/published scorecard is M5** — here, land the client scenarios + the score. If the score falls short, raise it with the gap analysis — do not redefine the bar. |
| M3b-12 | Dialyzer clean; CI green on `task/0.6.0-m3b`. | `rebar3 dialyzer` exit 0; CI (compile+xref+eunit+CT+proper+dialyzer+cover) green on the branch. | serious | dev plan M3b DoD | open | | |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
symmetry features. `correctness` = a guarantee the feature claims. `polish` =
hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M4+

_(Filled in at close — e.g. the cross-node test mechanism and whether it should
migrate onto M4 transports; modules still in `cover_excl_mods`.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 12. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
