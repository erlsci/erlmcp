# CC Prompt — erlmcp 0.6.0, Milestone M3a (Client request API)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M3a closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M3a only**: make
`erlmcp_client_session` a full *consumer* of the M2 server surface — the client
request API (tools/resources/prompts/logging/completion), pagination consumption,
progress receipt, cancellation issuance, and notification handling — and delete the
legacy client. **No sampling, roots, elicitation, or server-initiated requests** —
that's M3b. **M3a depends on M1** (the `client_session` spine) **and M2a/M2b** (the
server it talks to); reuse their patterns rather than reinventing them.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M3a-client-request-api-ledger.md`** — the M3a ledger
   (rows M3a-1…M3a-15). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first** and follow its own
   loading instructions.
4. **`src/erlmcp_client_session.erl`** — the M1 spine you extend (`pending`
   correlation map, `next_id`, `send_request/4`, `uninitialized`/`operational`
   states).
5. **`docs/0.6.0/milestones/M1-recore-ledger.md`** (M1-6, M1-8, M1-10 — client
   core, ctx, correlation) and **`M2a-…-ledger.md`** + **`M2b-…-ledger.md`** — the
   server endpoints + the cursor/`list_changed` shapes you must consume verbatim.
6. **`docs/0.6.0/planning/phase2-idiomatic-erlmcp.md`** — §3 (sessions/workers), §7
   (correlation), §8 (capabilities).

## Locked decisions (non-negotiable)

- **JSON only via `erlmcp_codec`**; **`jesse`** at the boundary; **OTP 25+**; **no
  macros for logic**; **no shared records** across boundaries; **validate at the
  edge, crash in the interior**.
- **Reuse M1's correlation** (`pending` map keyed by request id, `next_id`) — do not
  build a second correlation mechanism. **Consume the server's opaque cursor as
  opaque** (treat `nextCursor` as a token; never parse it).
- **One client.** `erlmcp_client_session` is the only client; the legacy
  `erlmcp_client` is deleted this milestone.

## Tasks (keyed to ledger rows; suggested order)

**Phase A — request surface.**
1. **[M3a-1]** `tools/list` (follow cursor) + `tools/call`, correlated to the caller.
2. **[M3a-2]** `resources/list` + `resources/read`.
3. **[M3a-3]** `resources/templates/list` + templated read.
4. **[M3a-5]** `prompts/list` + `prompts/get` (with arguments).
5. **[M3a-7]** `completion/complete`.
6. **[M3a-6]** `logging/setLevel` + handle inbound `notifications/message`.

**Phase B — subscriptions, notifications, async.**
7. **[M3a-4]** `resources/subscribe`/`unsubscribe` + handle `notifications/resources/updated`.
8. **[M3a-10]** Handle `notifications/{tools,resources,prompts}/list_changed`.
9. **[M3a-8]** Deliver inbound `notifications/progress` to the originating caller by token.
10. **[M3a-9]** Cancellation issuance via `cancel/2` → `notifications/cancelled`; no late result reaches the caller.

**Phase C — cross-cutting, cleanup, example & gates.**
11. **[M3a-11]** Consistent client-side pagination consumption across all list calls (opaque cursor).
12. **[M3a-12]** Capability gating: only call endpoints the server advertised at `initialize`; fail fast locally otherwise.
13. **[M3a-13]** Delete legacy `erlmcp_client`; remove it from `cover_excl_mods`; bring `erlmcp_client_session` to ≥90%.
14. **[M3a-14]** A client example + `erlmcp_example_client_SUITE` exercising the whole request API against an M2 server.
15. **[M3a-15]** `rebar3 dialyzer` clean; CI green.

## Working protocol

- **Branch:** `task/0.6.0-m3a`, cut from `release/0.6.x` (after M2a/M2b are merged);
  PR into `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the
  closing commit.
- Raise amendments; never silently work around. Coverage (M3a-13): if a module can't
  honestly reach 90%, raise it — don't pad tests or silently re-exclude.
- Closing report: a per-row walk over all 15 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M3a (do NOT build)

Sampling, roots, elicitation, server-initiated (server→client) requests, client
capability advertisement of callback features, the cross-node round-trip, the client
conformance score — **all M3b**. New transports — **M4**. Tasks — **M6**. Build only
the client-as-consumer request surface + the legacy-client deletion.

## Done when

All 15 ledger rows reach a final status; the client example, Dialyzer, and CI are
green; the legacy `erlmcp_client` is gone; the closed ledger is submitted for CDC
review.
