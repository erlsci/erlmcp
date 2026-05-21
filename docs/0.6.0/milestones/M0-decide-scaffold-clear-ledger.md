# Milestone M0: Decide, scaffold, and clear the ground

> Per-milestone verification ledger (see the project `LEDGER_DISCIPLINE.md`). CC
> works against this ledger; CDC verifies every disposition independently against
> the actual commit state. No milestone advances until the ledger is fully closed.

**Goal (from `../planning/phase4-0.6.0-development-plan.md` M0):** a clean slate
and the decisions everything else depends on. All Verify commands are run from the
repo root unless noted. All rows start `open`.

**Decisions locked 2026-05-20** (recorded in dev plan M0 + §5): JSON = `jsx`
behind `erlmcp_codec`; schema validator = `jesse`; minimum OTP = 25+; coverage gate
= 90% now, ratcheting to 95% by M5; plus rebar3 profiles.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M0-1 | No `_new` fork modules remain in `src/`. | `test -z "$(ls src/*_new*.erl 2>/dev/null)"` — currently FAILS: `src/erlmcp_transport_stdio_new.erl`, `src/erlmcp_server_new.erl`. | serious | dev plan M0; principle #3 ("no parallel `_new` modules ever again") | open | | The two named files must be deleted, their useful logic re-seated on the new core. |
| M0-2 | The three overlapping server implementations are reduced to one supervised server. | `ls src \| grep -i server` resolves to the single chosen module — `erlmcp_server_new.erl` gone (M0-1), and the `erlmcp_server.erl` / `erlmcp_stdio_server.erl` overlap collapsed per Phase 2 design; no duplicate unsupervised server remains. | serious | dev plan M0; phase3 (three overlapping impls) | open | | Current set: `erlmcp_server.erl`, `erlmcp_server_new.erl`, `erlmcp_server_sup.erl`, `erlmcp_stdio_server.erl`. Final target shape per Phase 2 §3/§10. |
| M0-3 | Phantom `erlmcp_client_sup` removed from the app manifest. | `! grep -q erlmcp_client_sup src/erlmcp.app.src` — currently FAILS (present at `src/erlmcp.app.src:6`). | correctness | dev plan M0 | open | | Module is listed but does not exist. |
| M0-4 | No dispatch to nonexistent `*_tcp_new` / `*_http_new` transports. | `! grep -rnE "_tcp_new\|_http_new" src` — currently FAILS (`src/erlmcp_transport_sup.erl:24,26`). | correctness | dev plan M0 | open | | These references are why xref (M0-9) currently cannot be clean. |
| M0-5 | The locked M0 decisions are recorded in the dev plan. | `grep -q "locked 2026-05-20" docs/0.6.0/planning/phase4-0.6.0-development-plan.md` and §5 rows show "Resolved". | no-op (documentation) | this session | open | | Edits made; evidence = commit SHA pending first M0 commit. |
| M0-6 | The new module skeleton (Phase 2 §10) is stood up: empty modules + `-behaviour`/`-callback` declarations + `-spec`s. | The Phase 2 §10 module list exists under `src/` and `rebar3 compile` succeeds with them present. | correctness | dev plan M0; phase2 §10 | open | | Enumerate the exact module list from Phase 2 §10 when filling this row. |
| M0-7 | A `MIGRATION-0.5-to-0.6.md` stub exists. | `test -f docs/0.6.0/MIGRATION-0.5-to-0.6.md` (or repo-root equivalent). | polish | dev plan M0 | open | | Filled in as the `erlmcp` facade solidifies. |
| M0-8 | Project compiles with the new skeleton, zero warnings. | `rebar3 compile` exits 0 with no warnings (`{erl_opts,[...,warnings_as_errors]}` recommended). | serious | dev plan M0 DoD | open | | |
| M0-9 | `xref` is clean. | `rebar3 xref` exits 0 (no calls to undefined functions). | correctness | dev plan M0 DoD | open | | Blocked-by M0-1 and M0-4: the `_new`/phantom references are current xref failures. |
| M0-10 | A real coverage gate is configured (≥90%), and `--min_coverage=0` is retired. | rebar.config / Makefile / CI enforces ≥90% coverage; `! grep -rn "min_coverage=0" Makefile .github 2>/dev/null`. | correctness | dev plan M0; M5 | open | | `rebar.config` has `cover_enabled` (lines 45/64/165) but no minimum gate today; the `--min_coverage=0` is likely in the Makefile/CI, not rebar.config — locate and replace. |
| M0-11 | CI is green on the new skeleton. | The CI workflow runs `compile` + `xref` + `eunit` and passes on the M0 branch. | correctness | dev plan M0 DoD | open | | |

### Significance legend
`serious` = architectural invariant whose violation undermines the re-core's
foundation. `correctness` = a guarantee M0 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Closure

_(Open. Filled at close.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 11. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
