# Milestone M5b: Docs rewrite & release/security automation

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** the documentation and release discipline that make the 0.6.0 re-core
usable and maintainable — every doc rewritten to match the new core, examples on the
new core, the migration guide finished, and SemVer/CHANGELOG + security automation
live. M5b is the second half of the former M5; it **depends on M5a** (docs describe
the scorecard-validated, spec-complete core).

**Locked decisions (carried):** OTP 25+ (no `-doc`/EEP-48; use edoc/ex_doc); the docs
describe the **new** core only (gen_statem session, per-request workers, transport
behaviour, registry discovery-only, validate-at-edge, discoverability surfaces). No
0.5-era claims. Examples all build and pass on the new core.

**Branch:** `task/0.6.0-m5b`, cut from `release/0.6.x` (after M5a lands); PR into
`release/0.6.x`. All Verify commands run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M5b-1 | `docs/architecture.md` rewritten to the new core: `gen_statem` session lifecycle, per-request worker isolation, cancellation-as-exit, transport behaviour, registry discovery-only (off hot path). | Doc describes the M1–M4 architecture; `grep` finds no stale 0.5 module names (`erlmcp_server`, `erlmcp_stdio_server`, `erlmcp_client`); reviewed against `src/`. | serious | dev plan M5b; closes D (stale docs) | open | | Currently dated Jun-2025 (0.5-era). |
| M5b-2 | `docs/protocol.md` rewritten to the 2025-11-25 surface erlmcp implements: tools/resources/prompts/logging/completion + sampling/roots/elicitation + discoverability (`instructions`/`_meta`/`annotations`/directory). | Doc matches the implemented method set; cross-checked against the session dispatch + conformance scorecard. | serious | dev plan M5b | open | | |
| M5b-3 | `docs/otp-patterns.md` rewritten: let-it-crash, supervision tree, validate-at-edge/crash-in-interior, per-request workers, cancellation-as-exit, opaque types. | Doc reflects the actual OTP patterns in `src/`; no stale patterns. | correctness | dev plan M5b | open | | |
| M5b-4 | `docs/api-reference.md` rewritten to the actual exported API: `erlmcp` facade, `erlmcp_client_session`, `erlmcp_schema`, `erlmcp_server_handler`, content constructors, transports. | Every API documented exists as an export (`grep` exports vs doc); no documented function is absent from `src/`. | serious | dev plan M5b; closes D | open | | |
| M5b-5 | `README.md` is accurate: what erlmcp 0.6.0 is, install, a quickstart that runs on the new core, status, doc links. | README quickstart code compiles/runs against the current API; no 0.5 claims. | serious | dev plan M5b | open | | |
| M5b-6 | `docs/0.6.0/MIGRATION-0.5-to-0.6.md` finished: removed modules, API changes, new patterns, how to port a 0.5 server/client. | The stub is filled; lists the deletions (`erlmcp_server`, `erlmcp_stdio_server`, `erlmcp_client`) and the new entry points. | serious | dev plan M5b; closes the M0-7 stub | open | | M0-7 left it a stub. |
| M5b-7 | All examples are on the new core and build/pass: calculator (M2a), weather (M2b), client (M3a), sampling (M3b); each referenced from the docs. | `rebar3 ct` runs the example suites green; docs link to them; no example uses a deleted module. | serious | dev plan M5b DoD ("examples all on the new core") | open | | |
| M5b-8 | SemVer policy stated + a maintained `CHANGELOG.md` with a 0.6.0 entry covering the re-core. | `CHANGELOG.md` exists with a 0.6.0 section; SemVer policy documented (README or CONTRIBUTING). | correctness | dev plan M5b (release discipline) | open | | |
| M5b-9 | Security/dependency automation: CodeQL (or equivalent) scanning + dependabot (or equivalent) dependency updates wired in CI. | The workflow files exist and are referenced by CI; a scan runs on push/PR. | correctness | dev plan M5b (security automation) | open | | "Consider equivalents" — pick what fits GitHub Actions. |
| M5b-10 | Docs verified against code (DoD gate) and CI green on `task/0.6.0-m5b`. | A cross-check (script or review) confirms no doc references a removed module/function; CI green on the branch. | serious | dev plan M5b DoD ("docs verified against code") | open | | The anti-drift gate for documentation. |

### Significance legend
`serious` = a DoD gate or anti-drift invariant (docs that lie about the code are
worse than no docs). `correctness` = a guarantee the milestone claims. `polish` =
hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M6+

_(Filled in at close — e.g. docs that will need a tasks section once M6 lands.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 10. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
