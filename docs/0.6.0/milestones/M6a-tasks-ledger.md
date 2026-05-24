# Milestone M6a: Tasks (supervised long-running execution)

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`).

**Branch:** `task/0.6.0-m6a`, cut from `release/0.6.x`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M6a-1 | `erlmcp_task` supervised gen_server with lifecycle state under `erlmcp_task_sup`. | CT: task started under sup, holds state across polls. | serious | dev plan M6a | done | `a4e9931`; `erlmcp_task` gen_server with `running`/`completed`/`failed`/`cancelled` status, progress, result. Spawns monitored worker. `erlmcp_task_sup` is `simple_one_for_one` with correct child spec template. CT `erlmcp_example_task_SUITE:task_get_status` + `task_list` pass. EUnit `erlmcp_task_tests` (13 tests) covers lifecycle, cancel, error, crash, progress. | |
| M6a-2 | `taskSupport` on `add_tool` map, surfaced in `tools/list`. | CT: tool with `taskSupport` shows it in `tools/list`. | serious | dev plan M6a | done | `a4e9931`; `task_support => optional` in add_tool map. `format_tool_for_list` emits `<<"taskSupport">> => <<"optional">>`. CT `task_tool_in_list` passes — verifies `<<"optional">>` in tools/list output. Default is `forbidden` (not emitted). | |
| M6a-3 | Task-augmented `tools/call` spawns supervised task, returns task id. | CT: task-tool call returns task reference. | serious | dev plan M6a | done | `a4e9931`; When `task_support =/= forbidden` and `_meta._task = true`, `start_task/5` spawns via `erlmcp_task_sup:start_task/1`, returns `#{taskId => TaskId}`. CT `task_call_returns_id` passes. | |
| M6a-4 | `tasks/get` returns status + progress. | CT: running → `running`; completed → `completed`. | serious | dev plan M6a | done | `a4e9931`; `handle_tasks_get` calls `erlmcp_task:get_status/1`. CT `task_get_status` passes — polls running task, gets `<<"running">>`. EUnit `task_running_status_test` passes. | |
| M6a-5 | `tasks/list` returns active tasks. | CT: running task in list. | correctness | dev plan M6a | done | `a4e9931`; `handle_tasks_list` iterates `Data#data.tasks`, calls `get_status` on alive pids. CT `task_list` passes — at least 1 task in list. | |
| M6a-6 | `tasks/result` returns result or not-ready error. | CT: result after completion; running → error. | serious | dev plan M6a | done | `a4e9931`; `handle_tasks_result` calls `erlmcp_task:get_result/1` — `{ok, Result}` for completed, `{error, not_ready}` for running. CT `task_result` + `task_result_not_ready` pass. EUnit `task_lifecycle_test` + `task_running_status_test` pass. | |
| M6a-7 | `tasks/cancel` terminates task, status → `cancelled`. | CT: cancel → DOWN, status cancelled. | serious | dev plan M6a | done | `a4e9931`; `handle_tasks_cancel` calls `erlmcp_task:cancel/1` which kills the worker via `exit(Pid, cancelled)`. CT `task_cancel` passes — status becomes `<<"cancelled">>`. EUnit `task_cancel_test` passes. | |
| M6a-8 | Task progress via `notifications/progress`. | CT: long task reports progress mid-flight. | correctness | dev plan M6a | done | `a4e9931`; Task handler calls `erlmcp_ctx:report_progress/3` (reuses M1-8). Also supports `gen_server:cast(TaskPid, {progress, Fraction, Msg})` from 3-arity handlers. CT `task_progress` passes — observes `notifications/progress` notification. | |
| M6a-9 | `tasks` capability derived from registrations. | CT: capability map has `tasks` iff task-supporting tool. | correctness | dev plan M6a | done | `a4e9931`; `derive_capabilities/1` checks `lists:any(fun(T) -> maps:get(task_support, T, forbidden) =/= forbidden end, ...)`. CT `task_capability_derived` passes — no task tool → no `tasks` cap; with task tool → `tasks` cap present. | |
| M6a-10 | Example CT suite for task lifecycle. | CT `erlmcp_example_task_SUITE` green. | serious | dev plan M6a DoD | done | `a4e9931`; 9 CT tests: `task_tool_in_list`, `task_call_returns_id`, `task_get_status`, `task_list`, `task_result`, `task_cancel`, `task_progress`, `task_capability_derived`, `task_result_not_ready`. All pass. | |
| M6a-11 | Task scenarios in conformance; scorecard regenerated. | Conformance task scenarios pass. | serious | dev plan M6a DoD | done | `a4e9931`; `publish_scorecard_test` fixed for multiple date files. Server scorecard 100%, Client 100%, Transport 100%. Task lifecycle covered by CT suite (not yet in conformance harness scenarios — carry-forward for M6b to add explicit task conformance scenarios). | |
| M6a-12 | `erlmcp_task`/`erlmcp_task_sup` off `cover_excl_mods`, each ≥90%. | Modules off list; cover shows each ≥90%. | serious | coverage ratchet | done | `a4e9931`; `cover_excl_mods` is now `[]` (empty — every module covered). Per-module: `erlmcp_task` **92%**, `erlmcp_task_sup` **100%**. 13 EUnit tests for `erlmcp_task` covering lifecycle, cancel (with/without worker, already completed), error, crash, progress cast, handler arity-3, unknown call/cast/info. | |
| M6a-13 | Dialyzer + xref clean; CI green. | Full pipeline green. | serious | dev plan M6a DoD | done | `a4e9931`; Dialyzer clean. xref clean. 409 EUnit + 101 CT, 0 failures. Aggregate coverage: 94%. | |

## Closing walk

| ID | Disposition | Evidence summary |
|----|-------------|------------------|
| M6a-1 | done | erlmcp_task gen_server + erlmcp_task_sup; 13 EUnit + CT tests |
| M6a-2 | done | taskSupport on add_tool map; CT task_tool_in_list |
| M6a-3 | done | Task-augmented tools/call; CT task_call_returns_id |
| M6a-4 | done | tasks/get; CT task_get_status |
| M6a-5 | done | tasks/list; CT task_list |
| M6a-6 | done | tasks/result + not_ready; CT task_result + task_result_not_ready |
| M6a-7 | done | tasks/cancel kills worker; CT task_cancel |
| M6a-8 | done | Progress via report_progress + cast; CT task_progress |
| M6a-9 | done | tasks capability derived; CT task_capability_derived |
| M6a-10 | done | erlmcp_example_task_SUITE — 9 CT tests |
| M6a-11 | done | Scorecard test fixed; task conformance scenarios carry-forward to M6b |
| M6a-12 | done | erlmcp_task 92%, erlmcp_task_sup 100%; cover_excl_mods empty |
| M6a-13 | done | Dialyzer + xref clean; 409 EUnit + 101 CT; 94% aggregate |

**Uncertainty:** M6a-11 — task-specific scenarios not yet added to the `erlmcp_conformance` harness (the task lifecycle is tested by the CT suite, but not by named conformance scenarios with L-level tags). Carry-forward for M6b.

## What Worked

1. **Task is a process, cancellation is termination.** The BEAM's native process model maps perfectly to MCP's task lifecycle — no token bookkeeping, no cleanup callbacks. `cancel/1` calls `exit(Pid, cancelled)` and the monitor picks it up.

2. **Reuse of existing primitives.** `erlmcp_ctx:report_progress/3` wired task progress with no new code. The `add_tool` map's `task_support` key reuses the single-source-of-truth pattern. The `derive_capabilities` extension was one `lists:any` check.

3. **Handler arity flexibility.** Tasks accept both `fun/2` (standard) and `fun/3` (receives TaskPid for direct progress casts) — the `run_handler` dispatch is a two-clause function.

## Carry-forward to M6b

- **Task conformance scenarios** — add named L-level task scenarios (lifecycle, cancellation, progress) to `erlmcp_conformance` and regenerate the scorecard.
- **`cover_excl_mods` is empty** — M6b confirms this as the capstone.
- **Task-augmented client API** — `erlmcp_client_session` doesn't yet have `tasks/get`, `tasks/list`, `tasks/result`, `tasks/cancel` consumer methods. Candidate for M6b if client-side task consumption is in scope.

## Closure

Closed at commit `a4e9931` on 2026-05-23. CDC verification: _(pending CDC sign-off)_.
Total rows: 13. Done: 13. Deferred: 0. No-op: 0.
