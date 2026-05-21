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
| M0-1 | No `_new` fork modules remain in `src/`. | `test -z "$(ls src/*_new*.erl 2>/dev/null)"` | serious | dev plan M0; principle #3 ("no parallel `_new` modules ever again") | done | `4ef4f9a`; `ls src/*_new*.erl` → "No such file or directory" | Deleted `erlmcp_server_new.erl` and `erlmcp_transport_stdio_new.erl`. Unique `_new` logic (registry-aware routing, TransportId-based init, async cast send) noted for M1 to re-seat on `gen_statem` session. |
| M0-2 | The three overlapping server implementations are reduced to one supervised server. | `ls src \| grep -i server` resolves to the single chosen module. | serious | dev plan M0; phase3 (three overlapping impls) | deferred | — | Re-entry: "M1 `erlmcp_server_session` lands." Count dropped from 4→3 (deleted `erlmcp_server_new`), but collapsing `erlmcp_server.erl` + `erlmcp_stdio_server.erl` into one requires the M1 `gen_statem` session — doing it in M0 would be faking a done. |
| M0-3 | Phantom `erlmcp_client_sup` removed from the app manifest. | `! grep -q erlmcp_client_sup src/erlmcp.app.src` | correctness | dev plan M0 | done | `4ef4f9a`; `grep erlmcp_client_sup src/erlmcp.app.src` → no match | |
| M0-4 | No dispatch to nonexistent `*_tcp_new` / `*_http_new` transports. | `! grep -rnE "_tcp_new\|_http_new" src` | correctness | dev plan M0 | done | `4ef4f9a`; `grep -rnE "_tcp_new\|_http_new\|_stdio_new" src/` → no match | Also removed `_stdio_new` dispatch (M0-1 prereq). Transport sup now points to real modules. |
| M0-5 | The locked M0 decisions are recorded in the dev plan. | `grep -q "locked 2026-05-20" docs/0.6.0/planning/phase4-0.6.0-development-plan.md` and §5 rows show "Resolved". | no-op (documentation) | this session | no-op | grep passes on existing dev plan | Decisions were recorded in a prior commit before M0 branch was created. |
| M0-6 | The new module skeleton (Phase 2 §10) is stood up: empty modules + `-behaviour`/`-callback` declarations + `-spec`s. | The Phase 2 §10 module list exists under `src/` and `rebar3 compile` succeeds. | correctness | dev plan M0; phase2 §10 | done | `d0cc640`; 16 new modules created, `rebar3 compile` + `rebar3 xref` clean | Full §10 map: `erlmcp_session_sup`, `erlmcp_server_session` (gen_statem), `erlmcp_client_session` (gen_statem), `erlmcp_codec`, `erlmcp_model`, `erlmcp_schema`, `erlmcp_capabilities`, `erlmcp_ctx`, `erlmcp_server_handler` (behaviour), `erlmcp_transport_streamable_http`, `erlmcp_sampling` / `erlmcp_roots` / `erlmcp_elicitation` (behaviours), `erlmcp_task_sup`, `erlmcp_task`, `erlmcp_conformance` (test/). |
| M0-7 | A `MIGRATION-0.5-to-0.6.md` stub exists. | `test -f docs/0.6.0/MIGRATION-0.5-to-0.6.md` | polish | dev plan M0 | done | `c598f5f`; file exists with API mapping skeleton | |
| M0-8 | Project compiles with the new skeleton, zero warnings. | `rebar3 compile` exits 0 with no warnings. | serious | dev plan M0 DoD | done | `d0cc640`; `rebar3 compile` → clean, exit 0 | |
| M0-9 | `xref` is clean. | `rebar3 xref` exits 0. | correctness | dev plan M0 DoD | done | `4ef4f9a` (unblocked by M0-1/M0-4); `rebar3 xref` → clean, exit 0 | Was blocked by `_new`/phantom references; clean after M0-1 + M0-4. |
| M0-10 | A real coverage gate is configured (≥90%), and `--min_coverage=0` is retired. | `! grep -rn "min_coverage=0" Makefile .github 2>/dev/null` | correctness | dev plan M0; M5 | done | `092bd61`; `.github/workflows/ci.yml:36` changed `--min_coverage=0` → `--min_coverage=90` | |
| M0-11 | CI is green on the new skeleton. | The CI workflow runs `compile` + `xref` + `eunit` and passes on the M0 branch. | correctness | dev plan M0 DoD | open | — | Requires pushing the `0.6.0-m0` branch and observing CI. Local equivalent passes: compile + xref + eunit all clean. |

### Significance legend
`serious` = architectural invariant whose violation undermines the re-core's
foundation. `correctness` = a guarantee M0 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Closure

_(Open. M0-11 awaits CI push; M0-2 deferred to M1.)_
Total rows: 11. Done: 8. Deferred: 1. No-op: 1. Open: 1 (M0-11, pending push).
