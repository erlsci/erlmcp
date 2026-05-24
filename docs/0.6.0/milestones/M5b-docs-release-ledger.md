# Milestone M5b: Docs rewrite & release/security automation

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`).

**Branch:** `task/0.6.0-m5`, on `release/0.6.x`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M5b-1 | `docs/architecture.md` rewritten to the new core. | No stale 0.5 module names; reviewed against `src/`. | serious | dev plan M5b | done | `db03e58`; Rewritten — gen_statem sessions, per-request workers, transport behaviour, registry discovery-only, schema validation, discoverability, supervision tree, conformance. `grep` for `erlmcp_server\b`, `erlmcp_stdio_server`, `erlmcp_client\b` → 0 matches. | |
| M5b-2 | `docs/protocol.md` rewritten to 2025-11-25 surface. | Matches implemented method set. | serious | dev plan M5b | done | `db03e58`; Full L0–L4 coverage: tools/resources/prompts/logging/completion + sampling/roots/elicitation + discoverability + capabilities + pagination. | |
| M5b-3 | `docs/otp-patterns.md` rewritten. | Reflects actual OTP patterns in `src/`. | correctness | dev plan M5b | done | `db03e58`; Let-it-crash, supervision tree, validate-at-edge, per-request workers, cancellation-as-exit, opaque types, transport behaviour, dependency injection (stdio DI). | |
| M5b-4 | `docs/api-reference.md` rewritten to actual exports. | Every documented function exists as an export. | serious | dev plan M5b | done | `db03e58`; Cross-checked: facade (server mgmt, tools, resources, prompts, logging, content constructors, setup), client session (lifecycle, request API, callbacks), schema builder, handler/callback behaviours, ctx, transports. | |
| M5b-5 | `README.md` accurate. | Quickstart runs on new core; no 0.5 claims. | serious | dev plan M5b | done | `db03e58`+`d3d3a42`; What it is, install, quickstart, status (93% coverage, 527 tests, 100% conformance), doc links, SemVer policy. Coverage badge updated to 93%. | |
| M5b-6 | Migration guide finished. | Lists deletions and new entry points. | serious | dev plan M5b | done | `db03e58`; Removed modules (erlmcp_server, erlmcp_stdio_server, erlmcp_client), API mapping table, tool registration before/after, architecture changes, porting instructions for server + client. | |
| M5b-7 | All examples on the new core. | CT suites green; docs link to them. | serious | dev plan M5b DoD | done | `db03e58`; Calculator (M2a), weather (M2b), client (M3a), sampling (M3b), task (M6a) — all CT suites pass. No example uses a deleted module. | |
| M5b-8 | SemVer policy stated. | README documents SemVer. | correctness | dev plan M5b | done | `db03e58`; SemVer policy in README. CHANGELOG deferred per owner preference (release notes in Git tags). | M5b-8 criterion mentioned CHANGELOG — owner decided against a CHANGELOG file; SemVer policy + Git tags is the release discipline. |
| M5b-9 | Security/dependency automation. | Workflow files exist. | correctness | dev plan M5b | done | `db03e58`; `.github/workflows/security.yml` (CodeQL on push/PR/weekly) + `.github/dependabot.yml` (GitHub Actions weekly). | |
| M5b-10 | Docs verified against code; CI green. | Cross-check clean; CI green. | serious | dev plan M5b DoD | done | `db03e58`+`d3d3a42`; `grep` for deleted modules in docs → 0 matches (outside migration context). README updated to reflect final 93% coverage and 527 tests. CI green. | |

## Closing walk

| ID | Disposition | Evidence summary |
|----|-------------|------------------|
| M5b-1 | done | architecture.md rewritten; no stale module refs |
| M5b-2 | done | protocol.md rewritten; full 2025-11-25 surface |
| M5b-3 | done | otp-patterns.md rewritten; includes DI pattern |
| M5b-4 | done | api-reference.md cross-checked against exports |
| M5b-5 | done | README accurate; 93% coverage, 527 tests, scorecard linked |
| M5b-6 | done | Migration guide finished; API mapping + porting |
| M5b-7 | done | All examples on new core; CT suites pass |
| M5b-8 | done | SemVer in README; CHANGELOG deferred (owner decision) |
| M5b-9 | done | CodeQL + dependabot wired |
| M5b-10 | done | Cross-check clean; CI green |

**Uncertainty:** M5b-8 — the ledger criterion mentioned a CHANGELOG file; the owner decided against it in favour of Git tag release notes. The SemVer policy IS documented.

## What Worked

1. **Net deletion.** The docs rewrite removed 846 lines and added 520 — shorter AND more accurate. Every claim was cross-checked against the code.

2. **The M5a CDC note was actionable.** "Link the scorecard artifact and reflect the final coverage state" was a concrete instruction that the closing pass executed (README coverage badge + scorecard link + architecture doc reference).

## Carry-forward to M7 / post-0.6

- **Docs will need a tasks section** when M7 adds any new task features.
- **api-reference.md** should be updated if M6a's client task methods or M6b's batch/icons features add exports not yet documented.

## Closure

Closed at commit `d3d3a42` on 2026-05-24 (retroactive close). CDC verification: _(pending CDC sign-off)_.
Total rows: 10. Done: 10. Deferred: 0. No-op: 0.
