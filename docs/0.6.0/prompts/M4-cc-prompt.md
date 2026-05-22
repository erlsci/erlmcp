# CC Prompt — erlmcp 0.6.0, Milestone M4 (Transports)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M4 closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M4 only**: production transports
behind the one `erlmcp_transport` behaviour, a **unified transport↔session contract**
so the session is transport-agnostic, and the same example server running unchanged
over stdio, TCP, and streamable HTTP. M4 also lands the **registry + supervision-tree
coverage** re-homed here at the M2b close. **No new protocol features** — the surface
is done (M2/M3); M4 is the transport layer + the coverage ratchet.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M4-transports-ledger.md`** — the M4 ledger (rows M4-1…M4-13).
   Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first** and follow its own
   loading instructions.
4. **`docs/0.6.0/planning/phase5-prior-art-reconciliation.md`** — §5 (what to harvest:
   `validate_transport_config/1`, the behaviour-conformance suite layout, the
   `start_{stdio,tcp,http}_setup` convenience functions) and §6 (keep/remove).
5. **`src/erlmcp_transport.erl`** (the behaviour — 5 callbacks) and
   **`src/erlmcp_transport_http.erl`** (the **reference** implementation) and
   **`test/erlmcp_transport_http_tests.erl`** (the per-transport suite template).
6. **`src/erlmcp_transport_stdio.erl`, `_tcp.erl`, `_streamable_http.erl`** — the
   transports you conform/implement. **`src/erlmcp_server_session.erl`** +
   **`erlmcp_client_session.erl`** — how the session consumes inbound transport data
   (`gen_statem:cast(Session, {transport_data, Data})` today).
7. **`docs/0.6.0/planning/phase2-idiomatic-erlmcp.md`** — §6 (transport behaviour).

## Locked decisions (non-negotiable)

- **JSON only via `erlmcp_codec`**; **`jesse`**/`validate_transport_config/1` at the
  edge; **OTP 25+**; **no macros for logic**; **no shared records**; **no boolean
  params** (tagged atoms/tuples); **validate at the edge, crash in the interior**.
- **`erlmcp_transport_http` is the reference. Do NOT revert it.** Bring stdio and tcp
  **up to** its shape (real `gen_server`, monitored owner, pid-based `send/2`,
  session-direct delivery). Harvest from prior art; don't reinvent.
- **Transports talk to the bound session directly** — no registry on the message hot
  path (the M1-13 invariant). The registry is discovery/binding only.

## Tasks (keyed to ledger rows; suggested order)

**Phase A — the contract (do this first; everything rides on it).**
1. **[M4-1]** Reconcile the transport↔session contract. Today it diverges:
   `stdio` does `Session ! {transport_data, _}`, `http` does
   `Owner ! {transport_message, _}`, and the session handles
   `cast {transport_data, _}`. **Pick one inbound tag + one delivery mechanism** and
   apply it to all transports and both sessions; outbound is always the behaviour
   `send/2`. The session must not know which transport it's on.
2. **[M4-2]** `validate_transport_config/1` per transport type, at the edge.

**Phase B — the transports (all to the reference shape + behaviour).**
3. **[M4-3]** `erlmcp_transport_stdio` → reference shape; off `cover_excl_mods`; ≥90%.
4. **[M4-4]** `erlmcp_transport_tcp` → reference shape; off `cover_excl_mods`; ≥90%.
5. **[M4-5]** `erlmcp_transport_http` (HTTP + SSE) — confirm behaviour conformance +
   SSE inbound; keep it the reference.
6. **[M4-6]** `erlmcp_transport_streamable_http` — implement the current-spec
   streamable HTTP transport (it's a stub today); off `cover_excl_mods`; ≥90%.
7. **[M4-7]** `start_stdio_setup/2`, `start_tcp_setup/3`, `start_http_setup/3`
   (+ streamable) convenience setup in the facade — thin wrappers, no logic.

**Phase C — conformance, the DoD, coverage ratchet & gates.**
8. **[M4-8]** `erlmcp_transport_conformance_SUITE` — one suite, parameterized over
   every transport, driving the `erlmcp_transport` contract.
9. **[M4-9]** The **same example server, unchanged**, runs over stdio + TCP +
   streamable HTTP with an identical request/response exchange (the DoD).
10. **[M4-10]** Add transport-level scenarios to `erlmcp_conformance` (formal
    scorecard stays M5).
11. **[M4-11]** `erlmcp_registry` — tests + off `cover_excl_mods` + ≥90%; confirm
    M1-13's "no per-message routing" still holds under test.
12. **[M4-12]** Supervision tree — `erlmcp_app`, `erlmcp_sup`, `erlmcp_server_sup`,
    `erlmcp_session_sup`, `erlmcp_transport_sup` — tests + off `cover_excl_mods` + ≥90%.
13. **[M4-13]** `rebar3 dialyzer` clean; CI green.

## Working protocol

- **Branch:** `task/0.6.0-m4`, cut from `release/0.6.x` (after M3a/M3b land); PR into
  `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the
  closing commit.
- Raise amendments; never silently work around. **Coverage (M4-3/4/6/11/12): if a
  module can't honestly reach 90%, raise it with a gap analysis — do not pad tests,
  silently re-exclude, or mark `done` at sub-90% without raising it.** (This is the
  exact issue caught on M3a-13; don't repeat it.)
- After M4, `cover_excl_mods` should list **only** `erlmcp_task` + `erlmcp_task_sup`
  (M6). If anything else remains, justify it in the closing report.
- Closing report: a per-row walk over all 13 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M4 (do NOT build)

New protocol features (done in M2/M3). The formal published conformance scorecard +
docs rewrite — **M5**. Tasks — **M6**. Do not revert or re-architect
`erlmcp_transport_http`. Do not reintroduce registry hot-path routing.

## Done when

All 13 ledger rows reach a final status; the same example server runs unchanged over
stdio/TCP/streamable HTTP; the behaviour-conformance suite is green across all
transports; the registry + supervisors are tested and out of `cover_excl_mods`
(leaving only the M6 task modules); Dialyzer and CI are green; the closed ledger is
submitted for CDC review.
