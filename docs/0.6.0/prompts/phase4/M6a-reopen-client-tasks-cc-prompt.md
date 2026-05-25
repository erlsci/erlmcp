# CC Prompt — erlmcp 0.6.0, M6a RE-OPEN (client task consumer API + M6a-11 re-disposition)

> Imperative brief for **CC**. M6a is **re-opened** on `task/0.6.0-m6a`. Two things:
> a disposition correction, and an **intentional scope increase** (owner-directed) to
> add the client-side task consumer API. **CDC re-runs the Verify commands and reads
> the diffs — not the summary — before M6a closes.**

## Why we're re-opening

1. **M6a-11 is mis-dispositioned.** It's marked `done`, but its criterion — *"task
   scenarios in `erlmcp_conformance`; scorecard regenerated"* — is not met: your own
   evidence, uncertainty note, and carry-forward all say the task scenarios are *not*
   in the conformance harness and are carried to M6b. Transparent, but the status label
   is wrong (and the totals read "Deferred: 0"). It must be `deferred`.
2. **Scope increase (owner decision):** M6a built the *server* task surface, but
   `erlmcp_client_session` has no way to *consume* it — no `tasks/get|list|result|cancel`
   consumer methods. `tasks/*` are client→server requests, so a symmetric client (the
   M3 goal) needs them. We're adding them to M6a now rather than deferring, so all task
   work lives in one milestone.

## Read before coding (in this order)

1. **`docs/0.6.0/milestones/M6a-tasks-ledger.md`** — the ledger you're amending.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — disposition rules (`done`/`deferred`/`no-op`).
3. **`priv/ai/erlang/SKILL.md`** — house style; load first.
4. **`src/erlmcp_client_session.erl`** — the M3a client request API you extend. Note
   the **reuse points**: the `pending` correlation map + `next_id` (M1), and
   `check_capability/2` capability gating (M3a-12). The existing consumer methods
   (`list_tools/1`, `call_tool/3`, `list_resources/1`, `read_resource/2`,
   `get_prompt/3`, …) are the naming + structure template.
5. **`src/erlmcp_server_session.erl`** — the **server** `tasks/*` handlers already
   exist (M6a-4..7: `handle_tasks_get`/`_list`/`_result`/`_cancel`); the client talks
   to them. Don't change the server side.

## Locked decisions (non-negotiable)

- JSON via `erlmcp_codec`; OTP 25+; no macros for logic; no shared records; validate at
  the edge; **no boolean params**.
- **Reuse, don't reinvent:** correlate task responses via the existing M1 `pending`
  map (the same path `call_tool` uses); gate on the server's advertised `tasks`
  capability via the existing `check_capability/2` (M3a-12). Do **not** add a parallel
  correlation or capability mechanism.
- **Per-module coverage (standing rule, now in CLAUDE.md):** `erlmcp_client_session`
  must stay ≥90% with the new methods. "Untested" ≠ "unreachable"; dead code is deleted;
  a true ceiling needs line-level proof.

## Tasks

### Phase A — fix the disposition (no code)

1. **Re-disposition M6a-11** from `done` → **`deferred`**, re-entry **M6b-5** (which
   already reads "regenerated to include … (and M6a's task scenarios)"). Update the row
   Status, the closing-walk line, and the **totals** (now Done: 14, Deferred: 1 once
   Phase B lands — see Phase C). Keep the honest evidence you already wrote.

### Phase B — add the client task consumer API (the scope increase)

2. **[M6a-14]** Add task consumer methods to `erlmcp_client_session`, issuing the
   protocol methods and correlating via the M1 `pending` map:
   - `list_tasks/1` → `tasks/list`
   - `get_task/2` (taskId) → `tasks/get`
   - `get_task_result/2` (taskId) → `tasks/result`
   - `cancel_task/2` (taskId) → `tasks/cancel`
   (Match the existing M3a method naming/shape; final names your call, but keep the
   convention.) Each is gated by `check_capability(<<"tasks">>, …)` — calling a
   `tasks/*` method against a server that didn't advertise the `tasks` capability fails
   fast client-side, no request sent.

3. **[M6a-15]** A client example + CT suite drives a **server task end-to-end through
   the client's typed API**: trigger a task-augmented `tools/call`, poll `get_task`
   (running → completed), `list_tasks` shows it, `get_task_result` returns the result;
   and a cancel path (`cancel_task` on a running task → status `cancelled`, no late
   result to the caller). `erlmcp_client_session` holds ≥90% with the new methods.

### Phase C — re-verify the gates + close

4. **Re-verify [M6a-13]:** with the new client code, `rebar3 dialyzer` + `xref` clean,
   full CI green, **`cover_excl_mods` stays `[]`**, and report the new aggregate +
   `erlmcp_client_session` per-module number. Update M6a-13's evidence with the new
   commit SHA.
5. **Update the ledger:** add rows M6a-14 and M6a-15 (with real evidence); note the
   **scope increase** in the milestone goal/header (client-side task consumption added
   by owner decision, 2026-05-23); update the closing walk; refresh the
   **Carry-forward** — remove the now-resolved "Task-augmented client API" item, keep
   the "Task conformance scenarios → M6b-5" item (that's M6a-11's re-entry).
6. **Closure block:** new closing commit SHA + date; **Total rows: 15. Done: 14.
   Deferred: 1 (M6a-11). No-op: 0.** Leave the CDC line **pending** — do not
   self-certify it.

## Verify (what CDC will re-run)

- M6a-11 Status = `deferred`, re-entry M6b-5; totals reflect Done 14 / Deferred 1.
- `grep -n "list_tasks\|get_task\|cancel_task" src/erlmcp_client_session.erl` shows the
  new exports; they correlate via `pending` and gate via `check_capability`.
- CT: client consumes a server task end-to-end (poll → result; cancel → cancelled).
- `cover_excl_mods` is `[]`; `erlmcp_client_session` ≥90%; Dialyzer/xref/CI green.

## Out of scope

- **Task conformance scenarios** — those are M6b-5 (M6a-11's re-entry); do NOT add them
  here. - No server-side `tasks/*` changes (done). No `_meta`/icons/batch (M6b). No new
  features beyond the four client consumer methods + their example/tests.

## Done when

M6a-11 reads `deferred` (re-entry M6b-5); the client task consumer API
(`list_tasks`/`get_task`/`get_task_result`/`cancel_task`) works end to end with
capability gating; `erlmcp_client_session` ≥90% and `cover_excl_mods` empty;
Dialyzer/xref/CI green; the ledger is updated to 15 rows (14 done, 1 deferred) with the
scope increase recorded; submitted for CDC sign-off.
