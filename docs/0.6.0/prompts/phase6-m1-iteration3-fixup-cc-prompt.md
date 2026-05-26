# CC Prompt — Phase 6 / P6-M1 iteration 3 (consolidated fix-up)

> Imperative brief for **CC**. This is a **focused correction**, not a new
> milestone. CDC reviewed iterations 1–2 (commits `348b51b`…`a47dbba`) and found
> the architecture sound but two coupled problems remaining: the coverage gate
> does not actually pass, and the conformance harness was left on the old API by
> the refactor (3 "cancelled" tests). **Iteration budget: this is iteration 3 of
> 5** on the P6-M1 ledger. Every item below is a **MUST** — there are no
> optional items in this pass. Read all of it before editing.

## Context — what CDC found (so you fix causes, not symptoms)

- The CI coverage gate is `rebar3 as test cover -v --min_coverage=90`, which
  checks **total** coverage. With `cover_excl_mods=[]` the aggregate is **82%**
  (P6-M1 modules are individually ≥90%, but out-of-scope modules drag the total:
  `erlmcp_client_session` 50%, `erlmcp_transport_streamable_http` 43%,
  `erlmcp_registry` 76%). So the gate **fails**; P6M1-14 was marked `done` against
  evidence that shows it does not pass. Do not lower the gate; make it pass
  honestly.
- The 3 "cancelled" conformance tests are **not** a scoring-threshold issue and
  **not** pre-existing. `erlmcp_conformance.erl` was migrated this session
  (`292d901`), and its harness still uses the **old** session API: e.g.
  `setup_client_pair` calls `erlmcp_server_session:start_link(#{transport => SB,
  ...})` and `erlmcp:register_handler(Server, ...)`. Under the new core the
  session takes a `responder` (not `transport`) and registration goes through
  `erlmcp_server`, so the server can't reply → `erlmcp_client_session:initialize/2`
  hangs → EUnit reports the test **cancelled**. (Arithmetic check: one failing
  scenario of 45 is 97.8%, well above the 87.5% bar — a single `fail` cannot
  produce this. The cause is a setup hang, not a low score.)
- **Decision (Duncan):** the client side is **in scope** for P6-M1 — it must
  compile and pass against the new core. Do not quarantine it.

## MUSTs (all required to close P6-M1)

1. **MUST repair the conformance harness to the new core API.** Update
   `test/erlmcp_conformance.erl` (and any helper it shares) so every server/
   client/transport scenario sets up against the new core: pass a `responder`
   (e.g. `erlmcp_reply:new_device/1`) instead of `transport =>`; register tools/
   resources/prompts/handlers through `erlmcp_server` (config-driven start or the
   server API), not via `register_handler` on a session pid. No scenario setup may
   hang or crash.

2. **MUST make the 3 cancelled tests run and pass.**
   `erlmcp_conformance_tests:server_scorecard_test/0`,
   `client_scorecard_test/0`, and `transport_scorecard_test/0` (and
   `publish_scorecard_test/0`) must execute to completion and satisfy their
   `Score >= 87.5` assertions. **MUST NOT lower the 87.5% threshold** to achieve
   this — raise the conformance, don't drop the bar.

3. **MUST get `erlmcp_client_session` working against the new core.** The client
   scorecard scenarios (`cs_initialize`, `cs_ping`, `cs_list_tools`, `cs_call_tool`,
   …) must pass over the in-VM bridge against an `erlmcp_server` + session. If the
   transport-behaviour redefinition (`init`/`serve`/`close`) left client paths
   inconsistent, fix the client to the new contract. If any client_session code is
   genuinely dead after the refactor, **delete it** and say what you removed — do
   not write tests that only exist to touch dead lines.

4. **MUST fix `scenario_pre_init_rejected`.** It currently probes pre-init
   rejection with `ping`, but the session **intentionally** answers `ping` in the
   uninitialized state (there is an explicit `handle_uninitialized_message(...
   <<"ping">> ...)` clause; ping-as-liveness pre-init is a deliberate MCP reading).
   Change the scenario to probe with a method that genuinely requires
   initialization (e.g. `tools/list`) and expect an error. Keep ping-pre-init as
   intended behaviour; add a one-line comment/doc note recording that this is a
   deliberate interpretation.

5. **MUST make the coverage gate pass for real:** `rebar3 as test cover -v
   --min_coverage=90` exits **0**. Achieve this by:
   - bringing **in-scope** modules to ≥90% with real tests — `erlmcp_client_session`
     (via item 3) and the P6-M1 spine modules (keep them ≥90%);
   - **scoping `cover_excl_mods`** for genuinely out-of-scope / doomed modules,
     each with an explicit **re-entry milestone and reason** recorded in the
     ledger Notes (the M1-16 precedent). At minimum: `erlmcp_transport_streamable_http`
     (the stub is **deleted in P6-M3** — do not spend effort covering doomed code).
     For any other module you exclude (e.g. client transports `erlmcp_transport_tcp`/
     `erlmcp_transport_http`, or `erlmcp_registry` if it is not P6-M1's to cover),
     the exclusion **MUST** be disclosed in the ledger with a named re-entry — **no
     silent exclusions**, and `erlmcp_registry`/`erlmcp_client_session` may not be
     excluded as a shortcut around items 1–3.

6. **MUST keep all other gates green** at the final commit: `rebar3 compile`
   warning-free (`warnings_as_errors`), `rebar3 xref` clean, `rebar3 dialyzer`
   clean, `rebar3 eunit` + Common Test 0 failures, `rebar3 proper -c` green, and
   `make check` exits **0**.

7. **MUST NOT redesign the accepted P6-M1 modules.** `erlmcp_server`,
   `erlmcp_reply`, the responder seam, the redefined behaviour, and the session's
   structure were accepted by CDC. This pass adds/repairs **tests and the client
   side**, and deletes dead code those tests expose. If a test reveals a real
   behavioural bug in an accepted module, fix the bug and note it — that is the
   only change permitted to accepted code.

8. **MUST reconcile the ledger.** CDC has amended the **P6M1-14** criterion to its
   correct form (per-module ≥90% for the P6-M1 set **plus** a scoped
   `cover_excl_mods` with named re-entry — see the ledger). Two new rows have been
   added: **P6M1-18** (conformance harness runs and all four scorecard tests pass
   at ≥87.5% — no threshold change) and **P6M1-19** (client side compiles and
   passes against the new core). Walk **all 19 rows**: set final Status + Evidence
   (commit SHA + Verify output) for each. No prose summary in place of the per-row
   walk; name any uncertainty.

## How to verify (these are the ledger Verify commands)

- Coverage: `rebar3 as test cover -v --min_coverage=90` → exit 0; per-module
  P6-M1 set ≥90%; every `cover_excl_mods` entry has a ledger re-entry note.
- Conformance: `rebar3 eunit --module=erlmcp_conformance_tests` → 0 failures, 0
  cancelled; server/client/transport scores ≥ 87.5%.
- pre_init: `grep -n "tools/list\|tools/call" test/erlmcp_conformance.erl` shows
  `scenario_pre_init_rejected` no longer uses `ping`; the scenario passes.
- Client: the `cs_*` scorecard scenarios pass; `erlmcp_client_session` ≥90% in the
  cover report.
- Full gate: `make check` exits 0.

## Working protocol

- **Branch:** continue on `task/0.6.0-p6m1`; PR into `release/0.6.x`.
- **Commit per coherent item**, updating ledger Status/Evidence in the same commit.
- **Raise, don't route around.** If repairing the client side reveals that a chunk
  of work genuinely belongs to a later milestone, raise an amendment with a named
  re-entry — do not silently exclude or skip. The one thing that is **not** an
  acceptable disposition here is lowering the 87.5% bar or the 90% gate.
- **Closing report:** per-row walk over all 19 rows.
- **Iteration cap:** this is iteration 3 of 5. If items 1–3 balloon beyond a
  focused fix (e.g. the client side turns out to be broadly broken), stop and
  raise it to CDC for a scope decision rather than burning iterations 4–5.

## Done when

`make check` exits 0 (coverage gate included), the conformance suite runs green
with the 87.5% bar intact, `erlmcp_client_session` passes against the new core and
is ≥90% covered, every `cover_excl_mods` exclusion is disclosed with a re-entry,
and all 19 ledger rows have a final Status + Evidence for CDC re-review.
