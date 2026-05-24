# Milestone M6a: Tasks (supervised long-running execution)

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`).

**Goal:** the headline native-strength feature — long-running tool execution as
supervised, pollable, cancellable task processes, plus the **client-side task
consumer API** (scope increase, owner decision 2026-05-23).

**Branch:** `task/0.6.0-m6a`, cut from `release/0.6.x`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M6a-1 | `erlmcp_task` supervised gen_server with lifecycle state under `erlmcp_task_sup`. | CT + EUnit. | serious | dev plan M6a | done | `a4e9931`; `erlmcp_task` gen_server (`running`/`completed`/`failed`/`cancelled`). `erlmcp_task_sup` `simple_one_for_one`. CT `erlmcp_example_task_SUITE` + 13 EUnit `erlmcp_task_tests`. | |
| M6a-2 | `taskSupport` on `add_tool` map, surfaced in `tools/list`. | CT `task_tool_in_list`. | serious | dev plan M6a | done | `a4e9931`; `task_support => optional` → `<<"taskSupport">> => <<"optional">>` in `tools/list`. | |
| M6a-3 | Task-augmented `tools/call` spawns supervised task, returns task id. | CT `task_call_returns_id`. | serious | dev plan M6a | done | `a4e9931`; When `task_support =/= forbidden` and `_meta._task = true`, `start_task/5` spawns via `erlmcp_task_sup`, returns `#{taskId => TaskId}`. | |
| M6a-4 | `tasks/get` returns status + progress. | CT `task_get_status`. | serious | dev plan M6a | done | `a4e9931`; `handle_tasks_get` calls `erlmcp_task:get_status/1`. | |
| M6a-5 | `tasks/list` returns active tasks. | CT `task_list`. | correctness | dev plan M6a | done | `a4e9931`; `handle_tasks_list` iterates alive task pids. | |
| M6a-6 | `tasks/result` returns result or not-ready error. | CT `task_result` + `task_result_not_ready`. | serious | dev plan M6a | done | `a4e9931`; `{ok, Result}` for completed, `{error, not_ready}` for running. | |
| M6a-7 | `tasks/cancel` terminates task, status → `cancelled`. | CT `task_cancel`. | serious | dev plan M6a | done | `a4e9931`; `cancel/1` kills worker via `exit(Pid, cancelled)`. | |
| M6a-8 | Task progress via `notifications/progress`. | CT `task_progress`. | correctness | dev plan M6a | done | `a4e9931`; Reuses `erlmcp_ctx:report_progress/3`. Also supports `gen_server:cast(TaskPid, {progress, ...})`. | |
| M6a-9 | `tasks` capability derived from registrations. | CT `task_capability_derived`. | correctness | dev plan M6a | done | `a4e9931`; `derive_capabilities/1` checks `lists:any` for `task_support =/= forbidden`. | |
| M6a-10 | Example CT suite for task lifecycle. | CT `erlmcp_example_task_SUITE` — 9 tests. | serious | dev plan M6a DoD | done | `a4e9931`; All 9 pass. | |
| M6a-11 | Task scenarios in `erlmcp_conformance`; scorecard regenerated. | Conformance task scenarios pass. | serious | dev plan M6a DoD | deferred | Task lifecycle tested by CT suite but **not** by named L-level conformance scenarios. | Re-entry: **M6b-5** (scorecard regeneration including task scenarios). |
| M6a-12 | `erlmcp_task`/`erlmcp_task_sup` off `cover_excl_mods`, each ≥90%. | `cover_excl_mods` empty; cover shows each ≥90%. | serious | coverage ratchet | done | `a4e9931`; `cover_excl_mods` is `[]`. `erlmcp_task` **92%**, `erlmcp_task_sup` **100%**. | |
| M6a-13 | Dialyzer + xref clean; CI green. | Full pipeline green. | serious | dev plan M6a DoD | done | `a4e9931`+`083976a`; Dialyzer clean. xref clean. 409 EUnit + 105 CT, 0 failures. `erlmcp_client_session` **91%**. Aggregate: **93%**. `cover_excl_mods`: `[]`. | |
| M6a-14 | Client task consumer API: `list_tasks/1`, `get_task/2`, `get_task_result/2`, `cancel_task/2` on `erlmcp_client_session`, gated by `tasks` capability. | CT `erlmcp_client_task_SUITE` — 4 tests. `grep` confirms exports + `check_capability`. | serious | Scope increase (owner, 2026-05-23) | done | `083976a`; 4 methods exported, each calls `request(Session, <<"tasks">>, ...)` with `check_capability` gating. `call_tool/4` gains `task => true` option. CT: poll_result, list, cancel, capability_gating. | |
| M6a-15 | Client task CT suite drives end-to-end: trigger task → poll → result; cancel mid-flight → cancelled. `erlmcp_client_session` ≥90%. | CT `erlmcp_client_task_SUITE` green; cover ≥90%. | serious | Scope increase (owner, 2026-05-23) | done | `083976a`; 4 CT tests: `client_task_poll_result` (call→get→result), `client_task_list` (call→list), `client_task_cancel` (call→cancel→status), `client_task_capability_gating` (no cap→fail fast). `erlmcp_client_session` **91%**. | |

## Closing walk

| ID | Disposition | Evidence summary |
|----|-------------|------------------|
| M6a-1 | done | erlmcp_task gen_server + task_sup; 13 EUnit + 9 CT |
| M6a-2 | done | taskSupport on add_tool map; CT task_tool_in_list |
| M6a-3 | done | Task-augmented tools/call; CT task_call_returns_id |
| M6a-4 | done | tasks/get; CT task_get_status |
| M6a-5 | done | tasks/list; CT task_list |
| M6a-6 | done | tasks/result + not_ready; CT task_result + task_result_not_ready |
| M6a-7 | done | tasks/cancel kills worker; CT task_cancel |
| M6a-8 | done | Progress via report_progress + cast; CT task_progress |
| M6a-9 | done | tasks capability derived; CT task_capability_derived |
| M6a-10 | done | erlmcp_example_task_SUITE — 9 CT tests |
| M6a-11 | **deferred** | Task conformance scenarios not in harness; re-entry M6b-5 |
| M6a-12 | done | erlmcp_task 92%, task_sup 100%; cover_excl_mods empty |
| M6a-13 | done | Dialyzer + xref clean; 409 EUnit + 105 CT; 93% aggregate |
| M6a-14 | done | Client task API (4 methods); CT client_task_SUITE (4 tests) |
| M6a-15 | done | Client task end-to-end; client_session 91% |

**Uncertainty:** M6a-11 is deferred — the task lifecycle is tested by the CT suite but not by named conformance scenarios. Re-entry at M6b-5.

## What Worked

1. **Task is a process, cancellation is termination.** The BEAM's native process model maps perfectly to MCP's task lifecycle — no token bookkeeping. `cancel/1` calls `exit(Pid, cancelled)` and the monitor picks it up.

2. **Reuse of existing primitives.** `erlmcp_ctx:report_progress/3`, the `add_tool` map's `task_support` key, `derive_capabilities`, and the client's `pending` correlation + `check_capability` gating — all reused with no new mechanisms.

3. **Symmetric client.** Adding `list_tasks`/`get_task`/`get_task_result`/`cancel_task` to the client was 4 functions following the existing `list_resources`/`read_resource` pattern. The `task => true` option on `call_tool/4` triggers task-augmented execution cleanly.

## Carry-forward to M6b

- **Task conformance scenarios (M6a-11 → M6b-5):** add named L-level task scenarios (lifecycle + cancellation + progress) to `erlmcp_conformance` and regenerate the scorecard.
- **`cover_excl_mods` is empty** — M6b confirms as capstone.

## Closure

Closed at commit `083976a` on 2026-05-23. CDC verification: _(pending CDC sign-off)_.
Total rows: 15. Done: 14. Deferred: 1 (M6a-11). No-op: 0.
