# CC Prompt — erlmcp 0.6.0, Milestone M3b (Server→client features: sampling, roots, elicitation)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M3b closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M3b only**: the inverted-
direction features. First build the **bidirectional request machinery** — the server
session must be able to *initiate* a request to its bound client and correlate the
response, and the client session must dispatch *inbound* server requests to callback
modules. On that, deliver **sampling** end-to-end, **roots**, and **elicitation**,
plus client-side capability advertisement. **M3b depends on M3a** (the client request
spine) and reuses M1's correlation pattern in the new direction.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M3b-server-to-client-features-ledger.md`** — the M3b
   ledger (rows M3b-1…M3b-12). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first** and follow its own
   loading instructions.
4. **`src/erlmcp_client_session.erl`** (post-M3a) and **`src/erlmcp_server_session.erl`**
   — the two FSMs you make symmetric. The server's inbound `pending`/worker model
   (M1-7) and the client's correlation map (M1-10) are the patterns to mirror.
5. **`src/erlmcp_ctx.erl`** — the **peer handle** (M1-8) is the server-side
   initiation entry point (a tool worker reaches the client through it).
6. **`src/erlmcp_sampling.erl`, `src/erlmcp_roots.erl`, `src/erlmcp_elicitation.erl`**
   — the callback behaviours (already stubbed: `handle_create_message/2`,
   `list_roots/1`, `handle_elicit/2`). Wire them; keep the contracts.
7. **`docs/0.6.0/planning/phase2-idiomatic-erlmcp.md`** — §3 (sessions/workers), §7
   (correlation), §8 (capabilities); the 2025-11-25 schema for the three methods.

## Locked decisions (non-negotiable)

- **JSON only via `erlmcp_codec`**; **`jesse`** at the boundary; **OTP 25+**; **no
  macros for logic**; **no shared records** across boundaries; **validate at the
  edge, crash in the interior**.
- **One correlation pattern, both directions.** The server's outbound-request path
  reuses the same `pending`-map + `next_id` shape as the client's — do not invent a
  parallel mechanism.
- **Callbacks run in per-request workers** (reuse the M1 worker model) so a slow or
  crashing callback is isolated, exactly as server tool handlers are.
- **Capabilities are derived, not hardcoded** — advertise a client feature only when
  its handler is registered.

## Tasks (keyed to ledger rows; suggested order)

**Phase A — bidirectional plumbing (build this first; everything else rides on it).**
1. **[M3b-1]** Server session can initiate a request to its client and correlate the
   response (outbound `pending` + id; reachable from a tool worker via `erlmcp_ctx`).
2. **[M3b-2]** Client session dispatches *inbound* server requests to callbacks;
   unknown method → `-32601`, session survives.
3. **[M3b-6]** Validate inbound server→client requests at the client boundary; invalid
   → `-32602`, callback never runs.

**Phase B — the three features.**
4. **[M3b-3]** Sampling end-to-end: server `sampling/createMessage` → client
   `erlmcp_sampling` callback (in a worker) → result back to the server worker.
5. **[M3b-4]** Roots: inbound `roots/list` → `erlmcp_roots:list_roots/1`; client emits
   `notifications/roots/list_changed`.
6. **[M3b-5]** Elicitation: inbound `elicitation/create` → `erlmcp_elicitation:handle_elicit/2`
   (accept/decline/cancel).
7. **[M3b-7]** Client advertises `sampling`/`roots`/`elicitation` at `initialize` only
   when the matching handler is registered.

**Phase C — example, cross-node, conformance & gates.**
8. **[M3b-8]** A server+client example using sampling + elicitation, with a CT suite.
9. **[M3b-10]** Client and server in **separate nodes** complete a sampling +
   elicitation round-trip (see the cross-node note below).
10. **[M3b-11]** `erlmcp_conformance` client scenarios report a client score ≥ rmcp's
    reference. Grow the harness incrementally; the formal scorecard is **M5**.
11. **[M3b-9]** Remove `erlmcp_sampling`/`roots`/`elicitation` from `cover_excl_mods`;
    gate ≥90%.
12. **[M3b-12]** `rebar3 dialyzer` clean; CI green.

## Cross-node note (M3b-10)

The DoD says "separate nodes," but **M4 owns the production transports** (TCP/HTTP).
You do **not** need to wait for M4: demonstrate the round-trip over **distributed
Erlang** (two nodes, the BEAM-native path) or two OS processes over the existing
stdio transport. If you find the round-trip genuinely cannot be shown without an M4
transport, **raise an amendment** with the analysis rather than pulling M4 work
forward or weakening the DoD.

## Working protocol

- **Branch:** `task/0.6.0-m3b`, cut from `release/0.6.x` (after M3a is merged); PR
  into `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the
  closing commit.
- Raise amendments; never silently work around. If M3b-11's score falls short of the
  rmcp reference, raise it with the gap analysis — do not redefine the bar.
- Closing report: a per-row walk over all 12 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M3b (do NOT build)

The client request API (done in M3a — consume it, don't rebuild). New transports —
**M4**. The formal published conformance scorecard — **M5** (M3b lands the client
scenarios + score only). Tasks — **M6**.

## Done when

All 12 ledger rows reach a final status; sampling + elicitation round-trip across
separate nodes; the client conformance score (≥ rmcp reference), Dialyzer, and CI are
green; the three callback modules are out of `cover_excl_mods`; the closed ledger is
submitted for CDC review.
