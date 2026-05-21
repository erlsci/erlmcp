# CC Prompt — erlmcp 0.6.0, Milestone M2b (Resources, prompts, logging, completion & conformance)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M2b closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M2b only**: the rest of the
server feature surface — resources (incl. templates + subscriptions), prompts,
logging, completion, pagination across those endpoints — plus a resource/prompt
example and the server conformance scorecard. **M2b depends on M2a having landed**
(tools, ergonomics, discoverability); reuse its schema/validation, pagination, and
`list_changed` patterns rather than reinventing them.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M2b-resources-prompts-logging-completion-ledger.md`** —
   the M2b ledger (rows M2b-1…M2b-14). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first** and follow its own
   loading instructions.
4. **`docs/0.6.0/milestones/M2a-tools-ergonomics-discoverability-ledger.md`** — the
   patterns to reuse: `tools/list` pagination (M2a-4), `list_changed` (M2a-10),
   schema/validation (M2a-1/6/7), capability advertisement (M2a-12).
5. **`docs/0.6.0/planning/phase2-idiomatic-erlmcp.md`** — §2 (validation), §8
   (capabilities), §9 (conformance & testing).

## Locked decisions (non-negotiable)

- **JSON only via `erlmcp_codec`**; **`jesse`** at the session boundary; **OTP 25+**;
  **no macros for logic**; **no shared records** across boundaries; **validate at
  the edge, crash in the interior**.
- **Reuse M2a's patterns** — pagination (opaque cursor), `list_changed`
  notifications, schema builder, capability-map derivation. One way to do a thing.

## Tasks (keyed to ledger rows; suggested order)

**Phase A — resources.**
1. **[M2b-1]** `resources/list` (paginated) + `resources/read`.
2. **[M2b-2]** Resource templates: `resources/templates/list` + templated read.
3. **[M2b-3]** `resources/subscribe`/`unsubscribe` + `notifications/resources/updated`.
4. **[M2b-4]** `notifications/resources/list_changed` (reuse the M2a-10 pattern).

**Phase B — prompts.**
5. **[M2b-5]** `prompts/list` (paginated) + `prompts/get` (with arguments).
6. **[M2b-6]** `notifications/prompts/list_changed`.

**Phase C — logging & completion.**
7. **[M2b-7]** `logging/setLevel` + `notifications/message` (make advertised logging real).
8. **[M2b-8]** `completion/complete` for prompt args / resource-template params.

**Phase D — cross-cutting, example & gates.**
9. **[M2b-9]** Consistent cursor/nextCursor pagination across resources/templates/prompts.
10. **[M2b-10]** Capability map advertises `resources`/`prompts`/`logging`/`completions`
    only when registered/supported (extends M2a-12).
11. **[M2b-11]** A resource+prompt example (e.g. weather with resources) with a CT suite.
12. **[M2b-12]** `erlmcp_conformance` server scenarios (L0–L4) report a server score
    ≥ rmcp's reference (87.5%). Grow the harness incrementally; the **formal/published
    scorecard is M5** — here, land the server scenarios + the score.
13. **[M2b-13]** Remove M2b modules from `cover_excl_mods`; gate ≥90%.
14. **[M2b-14]** `rebar3 dialyzer` clean; CI green.

## Working protocol

- **Branch:** `task/0.6.0-m2b`, cut from `release/0.6.x` (after M2a is merged in);
  PR into `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the
  closing commit.
- Raise amendments; never silently work around. If M2b-12's score falls short of
  87.5%, raise it with the gap analysis — do not redefine the bar.
- Closing report: a per-row walk over all 14 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M2b (do NOT build)

Tools/ergonomics/discoverability (done in M2a — extend, don't rebuild). Client-side
features — **M3**. New transports — **M4**. Tasks — **M6**. The formal published
conformance scorecard — **M5** (M2b lands the server scenarios + score only).

## Done when

All 14 ledger rows reach a final status; the resource/prompt example, the server
conformance score (≥ 87.5%), Dialyzer, and CI are green; the closed ledger is
submitted for CDC review.
