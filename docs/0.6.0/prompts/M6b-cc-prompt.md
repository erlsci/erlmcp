# CC Prompt — erlmcp 0.6.0, Milestone M6b (`_meta`, icons, batch & the finish line)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M6b closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M6b only**: the three remaining
protocol-completeness items — the `_meta` request/response channel, tool `icons`, and
session-level batch execution — plus the 0.6.0 coverage endpoint (empty
`cover_excl_mods`) and final release readiness. This is the **0.6.0 finish line**.
**No tasks work** — that's M6a (done).

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M6b-meta-icons-batch-finish-ledger.md`** — the M6b ledger
   (rows M6b-1…M6b-6). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first**.
4. **`src/erlmcp_ctx.erl`** (already carries `_meta` — M1-8), **`src/erlmcp.erl`** (the
   `add_tool` map), **`src/erlmcp_json_rpc.erl`** (`decode_and_classify_any` + `encode_batch`
   from M1-2 — the batch *parsing* you wire into session *execution*),
   **`src/erlmcp_server_session.erl`** (worker dispatch + `format_tool_for_list`).

## Locked decisions (non-negotiable)

- JSON via `erlmcp_codec`; `jesse` at the edge; OTP 25+; no macros for logic; no shared
  records; validate at the edge.
- **Reuse, don't reinvent:** `_meta` rides the `erlmcp_ctx` that already carries it;
  `icons` go on the single `add_tool` map (no parallel store); batch *execution* reuses
  the per-request worker model and M1-2's existing `decode_and_classify_any`/`encode_batch`
  — do not write a second batch parser.
- **Coverage endpoint:** after M6a the only excluded modules were the task ones (now
  implemented), so `cover_excl_mods` must end **empty**. stdio's `io:get_line` reader
  loop is the **sole** permitted named line-level exception; nothing else may be sub-90
  without line-level proof.

## Tasks (keyed to ledger rows; suggested order)

1. **[M6b-1]** `_meta` end to end: inbound request `_meta` → `erlmcp_ctx:meta/1` →
   handler may set `_meta` on its response.
2. **[M6b-2]** Tool `icons` settable on the `add_tool` map + surfaced in `tools/list`.
3. **[M6b-3]** Session-level batch **execution**: dispatch a batch of requests via the
   worker model, aggregate responses into a batch array; all-notification batch → no
   response; malformed/partial batch → per-member errors, session survives. Reuse
   M1-2's `decode_and_classify_any` + `encode_batch`.
4. **[M6b-4]** Make `cover_excl_mods` **empty**; confirm the gate holds with stdio's
   io-loop the only named exception.
5. **[M6b-5]** Regenerate the dated conformance scorecard with the `_meta`/icons/batch
   (+ M6a task) scenarios; scores still ≥ rmcp reference.
6. **[M6b-6]** `rebar3 dialyzer` + `xref` clean; full CI green — 0.6.0 release-ready.

## Working protocol

- **Branch:** `task/0.6.0-m6b`, cut from `release/0.6.x` (after M6a lands); PR into
  `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the closing
  commit. For M6b-4, report the final per-module table + confirm `cover_excl_mods` is `[]`.
- Raise amendments; never silently work around.
- Closing report: a per-row walk over all 6 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M6b (do NOT build)

Tasks (M6a — done). Docs rewrite (M5b). The M7 stretch list. Do not write a second
batch parser — wire the M1-2 one into session execution.

## Done when

`_meta`/icons/batch land; `cover_excl_mods` is empty with stdio the sole named
exception; the scorecard is regenerated and still ≥ reference; Dialyzer/xref/CI green;
the closed ledger is submitted for CDC review — and 0.6.0 is feature-complete.
