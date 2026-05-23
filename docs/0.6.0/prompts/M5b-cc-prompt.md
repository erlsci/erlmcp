# CC Prompt — erlmcp 0.6.0, Milestone M5b (Docs rewrite & release/security automation)

> Imperative brief for **CC**. Self-contained; load the linked docs before writing.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M5b closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M5b only**: rewrite every doc to
match the new core, put all examples on the new core, finish the migration guide, and
wire SemVer/CHANGELOG + security automation. **No code features, no conformance/spec/
coverage work** — that's M5a (done). M5b is documentation and release discipline.

## Read before writing anything (in this order)

1. **`docs/0.6.0/milestones/M5b-docs-release-ledger.md`** — the M5b ledger (rows
   M5b-1…M5b-10). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style (and EDoc guidance; OTP 25 → no
   `-doc`/EEP-48, use edoc/ex_doc).
4. **The current stale docs** — `docs/architecture.md`, `docs/protocol.md`,
   `docs/otp-patterns.md`, `docs/api-reference.md` (all Jun-2025/0.5-era),
   `README.md`, `docs/0.6.0/MIGRATION-0.5-to-0.6.md` (a stub).
5. **The code you're documenting** — `src/erlmcp_server_session.erl`,
   `erlmcp_client_session.erl`, `erlmcp.erl`, `erlmcp_schema.erl`, the transports —
   and the **M5a scorecard artifact** (the protocol surface, validated).

## Locked decisions (non-negotiable)

- Docs describe the **new core only**: `gen_statem` session, per-request worker
  isolation, cancellation-as-exit, transport behaviour, registry discovery-only,
  validate-at-edge, the discoverability surfaces. **No 0.5-era claims**, no references
  to deleted modules (`erlmcp_server`, `erlmcp_stdio_server`, `erlmcp_client`).
- **Docs must not lie about the code.** Every documented API must exist as an export;
  every example must build and pass on the new core. A doc that drifts from the code
  is the failure mode this milestone exists to kill.
- OTP 25+: edoc/ex_doc, not `-doc` attributes.

## Tasks (keyed to ledger rows; suggested order)

1. **[M5b-1]** Rewrite `docs/architecture.md` to the M1–M4 architecture.
2. **[M5b-2]** Rewrite `docs/protocol.md` to the implemented 2025-11-25 surface
   (tools/resources/prompts/logging/completion + sampling/roots/elicitation +
   discoverability).
3. **[M5b-3]** Rewrite `docs/otp-patterns.md` (let-it-crash, supervision, validate-at-
   edge, per-request workers, cancellation-as-exit, opaque types).
4. **[M5b-4]** Rewrite `docs/api-reference.md` to the actual exports — cross-check
   every documented function against `src/`.
5. **[M5b-5]** Rewrite `README.md` (what it is, install, a quickstart that runs on the
   new core, status, doc links).
6. **[M5b-6]** Finish `docs/0.6.0/MIGRATION-0.5-to-0.6.md` (deletions, API changes, how
   to port a 0.5 server/client).
7. **[M5b-7]** Put all examples on the new core (calculator, weather, client,
   sampling); link them from the docs; ensure their CT suites pass.
8. **[M5b-8]** Add `CHANGELOG.md` (0.6.0 entry) + state the SemVer policy.
9. **[M5b-9]** Wire CodeQL (or equivalent) + dependabot (or equivalent) in CI.
10. **[M5b-10]** Cross-check: no doc references a removed module/function; CI green.

## Working protocol

- **Branch:** `task/0.6.0-m5b`, cut from `release/0.6.x` (after M5a lands); PR into
  `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the
  closing commit.
- Raise amendments; never silently work around. If a doc claim can't be made true
  against the code, fix the doc — don't document an aspiration as fact.
- Closing report: a per-row walk over all 10 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M5b (do NOT build)

The conformance scorecard / test pyramid / specs / coverage — **all M5a** (done; link
to its artifact). New features. Tasks — **M6** (docs may note tasks as forthcoming but
do not document an unbuilt surface as present).

## Done when

All four docs + README + migration guide match the code; all examples build/pass on
the new core; `CHANGELOG.md` + SemVer + security automation are live; no doc
references a removed module/function; CI green; the closed ledger is submitted for CDC
review.
