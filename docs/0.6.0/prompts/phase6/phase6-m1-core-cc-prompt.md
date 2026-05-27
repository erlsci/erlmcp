# CC Prompt — erlmcp 0.6.0, Phase 6 / Milestone P6-M1 (Core spine)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before P6-M1 closes. This is the keystone milestone of Phase 6: get
> the spine right and stdio (P6-M2) and Cowboy HTTP (P6-M3) fall out cleanly.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **P6-M1 only**: the
transport-agnostic core spine. You will (1) separate the per-server **catalog**
from the per-conversation **session**, (2) introduce the opaque **responder** and
route all outbound through it, (3) carry a per-request reply target plus a session
push channel, (4) generalize `erlmcp_ctx` off the raw transport pid, (5) redefine
the `erlmcp_transport` behaviour, (6) make registration config-driven into the
server, and (7) add the outbound UTF-8 guard.

**You do NOT wire a transport end-to-end this milestone.** No stdio rebuild, no
`serve/1` gate, no Cowboy. The spine is proven with a **stub responder** (a test
pid that receives `{send, Json}`). stdio is P6-M2; HTTP is P6-M3.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/phase6-m1-core-spine-ledger.md`** — the P6-M1 ledger
   (rows P6M1-1…P6M1-17). Your definition of done; you report a disposition for
   every row.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`docs/0.6.0/planning/phase6-unified-transport-architecture.md`** — the Phase 6
   design. §1 (the defect you are fixing), §3 (target architecture: `erlmcp_server`,
   the session split, `erlmcp_reply`, the redefined behaviour), §4 (shared vs
   divergent), §5 (the HTTP boundary — context for why the seam must generalize).
4. **`docs/0.6.0/planning/phase2-idiomatic-erlmcp.md`** — §3 (concurrency &
   lifecycle), §5 (validate-at-edge), §6 (transport behaviour) for the existing
   conventions you are refactoring within.

**House style — load this first:** read `./priv/ai/erlang/SKILL.md` and follow its
own loading instructions (it indexes `priv/ai/erlang/guides/`; load
`11-anti-patterns.md` first, then `04-data-and-types.md` for the ETS/opaque-type
work, `07-otp-behaviours.md` for the behaviour redefinition, `06-processes-and-
concurrency.md` for the reply-correlation work). This is the operative coding
reference and supersedes general guidance.

## Locked decisions (non-negotiable)

- **JSON = `jsx` only inside `erlmcp_codec`.** No `jsx:` calls anywhere else (P6M1-11).
- **Schema validator = `jesse`** (not exercised this milestone; full validation is P6-M4).
- **Minimum OTP = 25+.** No features newer than OTP 25.
- **Coverage = 90% scoped**; the P6-M1 modules are *included* and must each hit the
  floor (P6M1-14). Per-module, not aggregate — a strong module may not carry a weak one.
- **Validate at the edge, crash in the interior.** The UTF-8 guard (P6M1-9) is an
  edge check at the emit boundary; do not scatter defensive `try` through the interior.
- **Opaque types, no shared records** across boundaries or in exported specs (P6M1-12).
- **One way to do a thing** — no `_new` modules. You are *editing* `erlmcp_server_session`
  and `erlmcp_ctx` in place, not forking them.

## Tasks (each maps to ledger rows; suggested build order)

**Phase A — the catalog owner.**
1. **[P6M1-1, P6M1-8]** Create `erlmcp_server`: owns the catalog
   (tools/resources/prompts + capabilities + identity) in a `protected` ETS table
   it owns; registration writes through it; sessions read it. Accept
   `tools`/`resources`/`prompts`/`handler` in the start config and register them
   during the server's own **synchronous** start, before it can be served. Opaque
   types only.

**Phase B — the responder.**
2. **[P6M1-3]** Create `erlmcp_reply`: an opaque responder with `send/2`. Implement
   the `{device, Pid}` kind (`Pid ! {send, Json}`) only. Unit-test over a test pid.

**Phase C — split the session onto the spine.**
3. **[P6M1-2]** Remove the catalog from `erlmcp_server_session`'s state; have it read
   tools/resources/prompts from its `erlmcp_server` by reference (ETS lookup or a thin
   server read API — your call, justify in the closing report). Registration calls now
   target the server.
4. **[P6M1-4]** Replace every `Transport ! {send, _}` in the session with
   `erlmcp_reply:send(Responder, Json)`. No bang-`{send,_}` left in the session.
5. **[P6M1-5]** Carry a **per-request reply target** in the in-flight request map (so
   the async worker round-trip replies to the originating request's responder), and a
   **session push channel** for unsolicited server→client messages.
6. **[P6M1-6]** Remove the raw transport pid from `erlmcp_ctx`; route progress and peer
   requests through the session (they already do — drop the vestigial field cleanly).
7. **[P6M1-10]** Remove the dead `initializing` state; states are
   `uninitialized → operational → shutting_down`.

**Phase D — the behaviour & the guard.**
8. **[P6M1-7]** Redefine the `erlmcp_transport` behaviour to the lifecycle
   (`init`/`serve`/`close`) + inbound-message-with-responder + outbound-via-responder
   contract. Delete the old `send(state(), iodata())` callback. No transport implements
   the new behaviour yet — that is P6-M2/M3.
9. **[P6M1-9]** Add the outbound UTF-8 well-formedness guard at the emit/codec boundary:
   an ill-formed binary fails closed, never emitted.

**Phase E — tests & gates.**
10. **[P6M1-13]** PropEr: a `prop_reply_correlation` (or equivalent) proving N requests
    with distinct responders each get their own response.
11. **[P6M1-14]** Include the P6-M1 modules in coverage; bring each to ≥90%.
12. **[P6M1-15, P6M1-16]** `rebar3 dialyzer` clean; `rebar3 compile` warning-free;
    `rebar3 xref` clean. Removing the catalog from the session will surface dangling
    references — fix them, don't suppress.
13. **[P6M1-17]** CI green on `task/0.6.0-p6m1`.

## Working protocol

- **Branch:** `task/0.6.0-p6m1`, cut from `release/0.6.x`; PR into `release/0.6.x`.
  (CI fires on `task/**` and `release/**`.)
- **Commit per ledger row** (or coherent group); in the same commit update that row's
  `Status`/`Evidence` (commit SHA + Verify output).
- **Raise, don't route around.** If a criterion is wrong, impossible, or needs a later
  milestone, raise an amendment (ledger Notes + flag to CDC); never silently work around.
  In particular: if a P6-M1 module can't honestly reach 90%, raise it with the exact
  uncovered lines — do not pad tests or re-exclude without a noted re-entry.
- **Closing report:** a per-row walk over all 17 rows — `done`+evidence,
  `deferred`+reason+re-entry, or `no-op`+rationale. No prose summary. Name uncertainty.
- **Iteration cap: 5.**
- **Subagents for lookup only**, never implementation, design, or judgment.

## Out of scope for P6-M1 (do NOT build)

- Any transport implementation against the new behaviour — stdio is **P6-M2**, Cowboy
  HTTP is **P6-M3**.
- The `serve/1` go-live gate and the per-server subtree supervisor — **P6-M2**.
- The `{http,_,_}` / `{sse,_}` responder kinds, the session manager, SSE/resumability —
  **P6-M3**.
- Full inbound/outbound JSON-Schema validation (jesse) — **P6-M4** (only the cheap UTF-8
  guard lands here).
- Example-server changes — **P6-M5**.

Build only the spine and prove it with a stub responder. Everything transport-specific waits.

## Done when

All 17 ledger rows have a final status; PropEr + Dialyzer + xref + coverage + CI all
green; the closed ledger is submitted for CDC review.
