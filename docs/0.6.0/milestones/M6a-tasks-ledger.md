# Milestone M6a: Tasks (supervised long-running execution)

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** the headline native-strength feature — long-running tool execution as
**supervised, pollable, cancellable task processes**, a lifecycle distinct from M1's
ephemeral per-request worker. `tasks/get|list|result|cancel` over `erlmcp_task` under
`erlmcp_task_sup`, with per-tool `taskSupport`. M6a is the first half of the former
M6; **M6b** lands `_meta`/icons/batch and the 0.6.0 finish line.

**Locked decisions (carried):** JSON via `erlmcp_codec`; `jesse` at the edge; OTP 25+;
validate at the edge, crash in the interior; no shared records; no `_new` forks; no
macros for logic. **Per-module coverage policy (standing):** a newly-included module
must individually reach the floor; "we didn't write the test" and "this function is
dead" are not unreachability — the former is covered, the latter is deleted; a true
ceiling needs a raised amendment with line-level proof.

**Reuse, don't reinvent:** cancellation-as-exit (M1-9), `erlmcp_ctx:report_progress/3`
(M1-8), the `add_tool` map as single source of truth (M2a-2/DISC-4), and capability
derivation (M2a-12).

**Branch:** `task/0.6.0-m6a`, cut from `release/0.6.x`; PR into `release/0.6.x`.
Depends on M1 + M2a. All Verify commands run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M6a-1 | `erlmcp_task` is a supervised, long-lived `gen_server` holding task lifecycle state (`running`/`completed`/`failed`/`cancelled`, progress, result), under `erlmcp_task_sup` (`simple_one_for_one`, started/terminated dynamically). | CT: a task process is started under the sup, holds state across polls, and is removed on completion/termination. | serious | dev plan M6a; Phase 2 §12 | open | | Distinct from the ephemeral per-request worker — a task outlives its triggering request. |
| M6a-2 | Per-tool `taskSupport` (`forbidden`/`optional`/`required`) is settable on the `add_tool` map and surfaced in `tools/list` (protocol-native `ToolExecution.taskSupport`). | CT: a tool registered with `taskSupport` shows it in `tools/list`; default is `forbidden`. | serious | dev plan M6a; 2025-11-25 `ToolExecution.taskSupport`; single-source `add_tool` map | open | | Behavioral execution semantics on the one registration map — not a parallel store. |
| M6a-3 | `tools/call` task-augmented execution: invoking a task-supporting tool with task semantics spawns a supervised task and returns a **task id** (not a blocking result); the task runs under `erlmcp_task_sup`. | CT: a task-tool call returns a task reference; the running work is a child of `erlmcp_task_sup`. | serious | dev plan M6a | open | | Reuses the worker dispatch, but the process is supervised + persistent. |
| M6a-4 | `tasks/get` returns a task's status and progress. | CT: poll a running task → `running` (+progress); after completion → `completed`. | serious | dev plan M6a | open | | |
| M6a-5 | `tasks/list` returns the active/recent tasks. | CT: a running task appears in `tasks/list`. | correctness | dev plan M6a | open | | |
| M6a-6 | `tasks/result` returns a completed task's result, and a well-formed error/empty for an incomplete one. | CT: result after completion; `running` task → not-ready error, not a crash. | serious | dev plan M6a | open | | |
| M6a-7 | `tasks/cancel` terminates an in-flight task: the supervised process is killed, status → `cancelled`, and no late result is delivered. | CT: cancel a running task → process `DOWN`, status `cancelled`, no result/late response. | serious | dev plan M6a; cancellation-as-exit (M1-9) | open | | Same BEAM primitive as request cancellation — the task *is* the process. |
| M6a-8 | A long-running task reports progress via `notifications/progress` keyed by its `progressToken`. | CT: a long task reports progress mid-flight; the client observes `notifications/progress`. | correctness | dev plan M6a; reuses M1-8/M2a-11 | open | | |
| M6a-9 | The `tasks` capability is advertised in `initialize` only when at least one task-supporting tool is registered (derived, not hardcoded). | CT: capability map advertises `tasks` iff a `taskSupport` tool exists. | correctness | dev plan M6a; Phase 2 §8; mirrors M2a-12 | open | | |
| M6a-10 | An example exercises a long-running, cancellable task tool end to end (call → get → list → result; and call → cancel mid-flight), with a CT suite. | CT `erlmcp_example_task_SUITE` drives the full task lifecycle green. | serious | dev plan M6a DoD | open | | The non-trivial example required by the DoD. |
| M6a-11 | `erlmcp_conformance` gains task scenarios (lifecycle + cancellation) and they pass. | The harness's task scenarios run and pass; the dated scorecard regenerates with them. | serious | dev plan M6a DoD; Phase 2 §9 | open | | Formal scorecard upkeep is M5a's artifact; M6a adds the task scenarios. |
| M6a-12 | `erlmcp_task` and `erlmcp_task_sup` leave `cover_excl_mods` and hold ≥90% each. | `cover_excl_mods` no longer lists either; `rebar3 cover` shows each ≥90%. | serious | coverage ratchet; standing per-module policy | open | | These are the last two excluded modules — M6b confirms the list is then empty. |
| M6a-13 | Dialyzer clean; xref clean; CI green on `task/0.6.0-m6a`. | `rebar3 dialyzer` exit 0; `rebar3 xref` clean; full pipeline green. | serious | dev plan M6a DoD | open | | |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the task
feature. `correctness` = a guarantee the feature claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M6b

_(Filled in at close — e.g. the now-empty `cover_excl_mods` for M6b to confirm; any
task scenario the scorecard still needs.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 13. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
