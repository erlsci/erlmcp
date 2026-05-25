# CC Prompt — erlmcp 0.6.0, Milestone M6a (Tasks)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M6a closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M6a only**: long-running tool
execution as **supervised, pollable, cancellable task processes** — the headline
native-strength feature. `tasks/get|list|result|cancel` over `erlmcp_task` under
`erlmcp_task_sup`, with per-tool `taskSupport`. **No `_meta`/icons/batch** — that's M6b.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M6a-tasks-ledger.md`** — the M6a ledger (rows M6a-1…M6a-13).
   Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first**.
4. **`src/erlmcp_task.erl`, `src/erlmcp_task_sup.erl`** — the stubs you implement (the
   last two modules in `cover_excl_mods`).
5. **`src/erlmcp_server_session.erl`** (worker dispatch, `handle_cancelled`,
   `report_progress` wiring), **`src/erlmcp_ctx.erl`** (progress token, cancellation),
   **`src/erlmcp.erl`** (the `add_tool` map) — the M1/M2a machinery you reuse.
6. **`docs/0.6.0/planning/m2-discoverability-design.md`** §2 (`ToolExecution.taskSupport`
   is protocol-native) and **`phase2-idiomatic-erlmcp.md`** §3,§12.

## Locked decisions (non-negotiable)

- JSON via `erlmcp_codec`; `jesse` at the edge; OTP 25+; no macros for logic; no shared
  records; validate at the edge; **no boolean params** (use `taskSupport` atoms).
- **A task is a supervised process** under `erlmcp_task_sup` — distinct from the
  ephemeral per-request worker. **Cancellation is termination** (reuse M1-9's
  cancellation-as-exit; the task *is* the process — no token bookkeeping).
- **Reuse, don't reinvent:** `erlmcp_ctx:report_progress/3` for task progress;
  capability derivation (M2a-12 pattern) for the `tasks` capability; the `add_tool` map
  as the single source of truth for `taskSupport` (no parallel store).
- **Coverage:** the task modules must individually reach ≥90%. "Untested" ≠
  "unreachable"; "dead code" is deleted, not amended. A true ceiling needs line-level
  proof.

## Tasks (keyed to ledger rows; suggested order)

**Phase A — the task process model.**
1. **[M6a-1]** `erlmcp_task` (supervised long-lived `gen_server`: status/progress/result
   state) under `erlmcp_task_sup` (`simple_one_for_one`, dynamic start/terminate).
2. **[M6a-2]** `taskSupport` (`forbidden`/`optional`/`required`) on the `add_tool` map +
   surfaced in `tools/list`.

**Phase B — the task surface.**
3. **[M6a-3]** `tools/call` task-augmented → spawn a supervised task, return a task id.
4. **[M6a-4]** `tasks/get` (status + progress).
5. **[M6a-5]** `tasks/list`.
6. **[M6a-6]** `tasks/result` (completed → result; running → not-ready error, no crash).
7. **[M6a-7]** `tasks/cancel` (terminate the task process; status `cancelled`; no late result).
8. **[M6a-8]** Task progress via `notifications/progress`.
9. **[M6a-9]** `tasks` capability derived (advertised iff a task-supporting tool exists).

**Phase C — example, conformance & gates.**
10. **[M6a-10]** `erlmcp_example_task_SUITE` — full lifecycle (call→get→list→result; call→cancel).
11. **[M6a-11]** Task scenarios in `erlmcp_conformance`; regenerate the dated scorecard.
12. **[M6a-12]** `erlmcp_task`/`erlmcp_task_sup` off `cover_excl_mods`, each ≥90%.
13. **[M6a-13]** `rebar3 dialyzer` + `xref` clean; CI green.

## Working protocol

- **Branch:** `task/0.6.0-m6a`, cut from `release/0.6.x`; PR into `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the closing
  commit, reporting per-module coverage for M6a-12.
- Raise amendments; never silently work around. Do not mark a coverage row `done` below
  90% without line-level proof of unreachability.
- Closing report: a per-row walk over all 13 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M6a (do NOT build)

`_meta` channel, icons, session-level batch execution, the empty-`cover_excl_mods`
capstone — **all M6b**. No docs (M5b). Do not build a token-based cancellation registry
(the supervised process *is* the handle).

## Done when

The task lifecycle works end to end (supervised, pollable, cancellable mid-flight); the
example + task conformance scenarios are green; `erlmcp_task`/`erlmcp_task_sup` are out
of `cover_excl_mods` at ≥90%; Dialyzer/xref/CI green; the closed ledger is submitted for
CDC review.
