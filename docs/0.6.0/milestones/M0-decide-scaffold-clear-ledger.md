# Milestone M0: Decide, scaffold, and clear the ground

> Per-milestone verification ledger (see the project `LEDGER_DISCIPLINE.md`). CC
> works against this ledger; CDC verifies every disposition independently against
> the actual commit state. No milestone advances until the ledger is fully closed.

**Goal (from `../planning/phase4-0.6.0-development-plan.md` M0):** a clean slate
and the decisions everything else depends on. All Verify commands are run from the
repo root unless noted. All rows start `open`.

**Decisions locked 2026-05-20** (recorded in dev plan M0 + §5): JSON = `jsx`
behind `erlmcp_codec`; schema validator = `jesse`; minimum OTP = 25+; coverage gate
= 90% **scoped to implemented modules** (skeletons + legacy-to-delete excluded via
`cover_excl_mods`), ratcheting to 95% over the whole codebase by M5; plus rebar3
profiles.

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
| M0-10 | A real coverage gate is configured (≥90%), and `--min_coverage=0` is retired. | `! grep -rn "min_coverage=0" Makefile .github 2>/dev/null` | correctness | dev plan M0; M5 | done | `092bd61`; `.github/workflows/ci.yml:36` changed `--min_coverage=0` → `--min_coverage=90` | Configured as specified. The flat-90% *value* proved wrong for M0 (CI hit 38% — see M0-12); the gate's existence/retirement of `=0` is still satisfied here. |
| M0-11 | CI is green on the new skeleton. | The CI workflow runs `compile` + `xref` + `eunit` + `cover` and passes on `task/0.6.0-m0`. | correctness | dev plan M0 DoD | done | Owner-confirmed CI green on `task/0.6.0-m0` (compile + xref + eunit + cover all pass), after M0-12. | CDC note: sandbox lacks the Erlang toolchain, so CI itself is the independent reproducer here; closed on the owner's observation of the green run. |
| M0-12 | Coverage gate scoped to implemented modules: `cover_excl_mods` excludes not-yet-implemented skeletons and legacy modules slated for replacement; gate passes at ≥90% over the included (implemented, staying) modules. | CI `cover -v --min_coverage=90` passes; `cover_excl_mods` in `rebar.config` matches the keep-vs-replace classification. | serious | **Amendment** — CI failure 2026-05-21 (flat gate vs empty skeletons); owner chose "scope to implemented modules". | done | `000bd27`; `rebar3 as test cover -v --min_coverage=90` → 2 included modules, both 100%, gate passes; CI green. CDC-audited: exclusions are all genuine skeleton/to-replace (each milestone-tagged); nothing implemented-and-staying is hidden. | Included: `erlmcp_transport` (100%), `erlmcp_transport_http` (100%). The included set is near-empty — this is honest: M0 added no new logic, and everything else is either a skeleton or legacy-to-replace. The gate gains teeth as M1+ lands real modules. Exclusion list: 15 skeletons + 13 legacy-to-replace (see `cover_excl_mods` in rebar.config for full list with milestone tags). |

### Significance legend
`serious` = architectural invariant whose violation undermines the re-core's
foundation. `correctness` = a guarantee M0 claims. `polish` = hygiene.

## What Worked

- Opening the ledger with **failing** Verify commands made the dead-code removals
  self-verifying — each grep flipped FAIL→PASS at the commit that closed its row.
- The CC↔CDC split caught a real spec defect: the flat-90% gate (M0-10) conflicted
  with the empty skeleton (M0-6), and only the CI `cover` step surfaced it. Vindicates
  "CI is the independent reproducer," especially where CDC's sandbox lacks the toolchain.
- The defect was handled by **amendment** (M0-12), not by silently rewriting M0-10 —
  the original row stayed honest about what it did; the new requirement was tracked.
- Clean linear convergence, well inside the 5-iteration cap.

## Carry-forward to M1 (do not drop)

1. Re-seat the unique `_new` logic from M0-1 (registry-aware routing, TransportId
   init, async-cast send) onto the `gen_statem` session.
2. Collapse `erlmcp_server` + `erlmcp_stdio_server` into `erlmcp_server_session`
   (the deferred M0-2).
3. Codec boundary: route all JSON through `erlmcp_codec`; no `jsx:` calls outside
   it (currently in `erlmcp_json_rpc`, `erlmcp_stdio_server`).
4. **Shrink `cover_excl_mods`:** as each M1-tagged module is re-seated, remove it
   from the exclusion list and hold it to 90% — `erlmcp_app`, `erlmcp_sup`,
   `erlmcp_server_sup`, `erlmcp_session_sup`, `erlmcp_transport_sup`,
   `erlmcp_server`→`erlmcp_server_session`, `erlmcp_json_rpc`, `erlmcp_registry`,
   `erlmcp_stdio`, `erlmcp_stdio_server`. This is what gives the coverage gate
   teeth; the M0 gate is intentionally near-vacuous.

## Closure

Closed at commit `000bd27` on 2026-05-21. CDC verification: this session —
independent reproduction of all file-state rows; `cover_excl_mods` classification
audited against the coverage report and the Phase 2 keep/replace intent;
compile/xref/eunit/cover confirmed via owner-observed CI (sandbox lacks the Erlang
toolchain, so CI is the reproducer for those rows).
Total rows: 12. Done: 10. Deferred: 1 (M0-2). No-op: 1 (M0-5). Open: 0.
