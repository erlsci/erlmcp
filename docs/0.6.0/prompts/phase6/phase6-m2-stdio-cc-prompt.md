# CC Prompt — erlmcp 0.6.0, Phase 6 / Milestone P6-M2 (stdio on the new shape)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before P6-M2 closes. This milestone turns the now-correct spine into a
> real working stdio transport and **structurally closes the startup race** that
> began this whole arc.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **P6-M2 only**: rebuild the
**stdio** transport onto the new core (the redefined `erlmcp_transport` behaviour +
the `erlmcp_reply` responder), start it **paused** behind a `serve/1` gate, fold
server + session + transport into a **per-server subtree**, and make
`start_stdio_setup/2` build-then-serve so the catalog is complete before a byte is
read. No HTTP/Cowboy (P6-M4), no full example rehab (P6-M6), no jesse payload
validation (P6-M5), no discoverability enrichment (P6-M3).

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/phase6-m2-stdio-ledger.md`** — the P6-M2 ledger (rows
   P6M2-1…P6M2-14). Your definition of done; you report a disposition for every row.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`docs/0.6.0/planning/phase6-unified-transport-architecture.md`** — §3.3
   (responder), §3.4 (behaviour), §3.5 (per-transport tiers / stdio as the
   degenerate one-connection case), §3.6 (`serve/1` gate), §1.4 (the race).
4. **`CLAUDE.md`** — especially *Never loosen a check to make it pass* and the
   coverage rule. **House style:** read `priv/ai/erlang/SKILL.md` first
   (`11-anti-patterns.md`, then `07-otp-behaviours.md`, `08-supervision-and-applications.md`,
   `06-processes-and-concurrency.md`).

## Locked decisions (non-negotiable)

- JSON via `jsx` inside `erlmcp_codec` only; `jesse` at the edge (not exercised here).
- Min OTP 25+. Dialyzer is gated to OTP 27+ — **run `make dialyzer` on 27 and 28**.
- Coverage 90% per-module, scoped via `cover_excl_mods`; **settle the M2 scope in
  your first commit** (P6M2-11), don't discover it at iteration 4.
- Validate at the edge, crash in the interior. Opaque types + accessors.
- **Never loosen a check to reach green** — no suppressions, no widened specs to
  silence dialyzer, no skipped tests. If a check looks wrong, **escalate** with
  `file:line`; do not loosen.

## Tasks (each maps to ledger rows; suggested build order)

**Phase A — rebuild the transport.**
1. **[P6M2-1]** `erlmcp_transport_stdio` implements `erlmcp_transport` (`init`/`serve`/
   `close`); drop the old `send(state(), iodata())` shape.
2. **[P6M2-2]** Start **paused**: do **not** spawn the stdin reader in `init/1`;
   `serve/1` spawns it. Keep `-noshell`, target the `user` device for real I/O
   (the lesson from the original stdio fix — don't trust the group leader).
3. **[P6M2-3]** Outbound through the responder: the transport is the `{device, Pid}`
   writer; the session emits via `erlmcp_reply:send/2`. No session-side direct stdout.

**Phase B — subtree + wiring.**
4. **[P6M2-4]** A per-server subtree supervisor over `{erlmcp_server,
   erlmcp_server_session, erlmcp_transport_stdio}`. Choose and **document** the
   restart strategy (`rest_for_one`/`one_for_all`) and child restart type
   (`temporary`/`transient`) — the three must live and die as a unit.
5. **[P6M2-5]** `start_stdio_setup/2` builds the subtree, registers the catalog
   **from `Config`** (server's synchronous start), then calls `serve/1`. One call,
   race impossible.

**Phase C — the race/EOF/purity guards.**
6. **[P6M2-6]** Race conformance test: register N tools + M resources + K prompts
   via config; assert `tools/list`/`resources/list`/`prompts/list` each return all
   of them over stdio. This is the regression guard for the original 4-of-7.
7. **[P6M2-9]** stdin EOF → clean subtree shutdown (OS process exits, no hang, no
   `reader_died` spew).
8. **[P6M2-10]** stdout = JSON-RPC only; logger → `standard_error` via
   `config/sys.config`.

**Phase D — acceptance.**
9. **[P6M2-7]** Harden `test/scripts/test_stdio_roundtrip.sh` against a
   **config-driven** server (a minimal test fixture, or a config-driven `simple` —
   do **not** do full example rehab here). Real `run.sh` + real stdin/stdout.
10. **[P6M2-8]** CT e2e: `initialize → ping → tools/list → tools/call → cancel`
    over the real stdio transport.

**Phase E — escape hatch & gates.**
11. **[P6M2-14]** Keep the dynamic path working (`start_server` +
    `start_transport(paused)` + manual register + explicit `serve/1`) with a test
    and a doc note that the caller owns gating; registering after `serve` is
    unsupported.
12. **[P6M2-11]** Coverage: include `erlmcp_transport_stdio` + the subtree sup at
    ≥90%; record the `cover_excl_mods` exclusions + re-entry milestones in the ledger.
13. **[P6M2-12, P6M2-13]** `make dialyzer` clean on 27 **and** 28; `make check`
    green; CI green on `task/0.6.0-p6m2`.

## Working protocol

- **Branch:** `task/0.6.0-p6m2`, cut from `release/0.6.x` **after P6-M1 merges**;
  PR back into `release/0.6.x`.
- **Commit per ledger row** (or coherent group); update Status/Evidence in the
  closing commit.
- **Raise, don't route around.** Wrong/impossible criterion → amendment with
  re-entry. A check that looks wrong → escalate `file:line`, never loosen.
- **Closing report:** per-row walk over all 14 rows. No prose summary. Name uncertainty.
- **Iteration cap: 5.** Settle coverage scope and the test-suite boundary early so
  iterations aren't spent on the churn that bit P6-M1.
- **Subagents for lookup only.**

## Out of scope for P6-M2 (do NOT build)

- HTTP/Cowboy, the session manager, SSE/resumability, the `{http,_,_}`/`{sse,_}`
  responder kinds — **P6-M4**.
- Full example rehabilitation — **P6-M6** (a minimal config-driven fixture for the
  round-trip test is fine; rewriting calculator/weather is not).
- jesse/MCP-schema payload validation — **P6-M5**.
- Discoverability enrichment (instructions, server block, `protocol_features`) —
  **P6-M3** (machinery) + **P6-M6** (example content).

## Done when

stdio runs on the new spine: paused-until-`serve`, responder-based I/O, a per-server
subtree, config-driven `start_stdio_setup` that closes the race by construction;
the race-conformance, round-trip, and e2e tests pass; EOF shuts down cleanly;
stdout is protocol-only; coverage scoped and ≥90% on the M2 modules; dialyzer clean
on 27/28 with zero suppressions; CI green — and all 14 ledger rows have a final
Status + Evidence for CDC review.
