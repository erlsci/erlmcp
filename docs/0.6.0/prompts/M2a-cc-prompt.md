# CC Prompt — erlmcp 0.6.0, Milestone M2a (Tools, ergonomics & discoverability)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M2a closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M2a only**: the tool-server
core on the M1 spine — the ergonomics layer, the full `tools/*` surface with real
input/output validation, and the discoverability layer. **No resources, prompts,
logging, completion, or conformance scorecard** — that's M2b.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M2a-tools-ergonomics-discoverability-ledger.md`** — the
   M2a ledger (rows M2a-1…M2a-16 + DISC-1…DISC-9). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first** and follow its own
   loading instructions (indexes `priv/ai/erlang/guides/`).
4. **`docs/0.6.0/planning/m2-discoverability-design.md`** — the discoverability
   design (single source of truth → `instructions` / `_meta` / directory tool;
   `_meta` key grammar; conformance boundary). Authoritative for DISC-1…DISC-9.
5. **`docs/0.6.0/planning/phase2-idiomatic-erlmcp.md`** — §1 (ergonomics without
   macros), §2 (validation wired at the edge), §8 (capabilities).
6. **`docs/0.6.0/milestones/M1-recore-ledger.md`** — what the spine already gives
   you (sessions, per-request workers, `erlmcp_ctx`, `erlmcp_json_rpc`, codec).

## Locked decisions (non-negotiable)

- **JSON only via `erlmcp_codec`** (no `jsx:` elsewhere).
- **`jesse`** is the validator, wired **at the session boundary before dispatch**.
- **OTP 25+**; **no macros for logic**; **no shared records** across boundaries or
  in exported specs; **validate at the edge, crash in the interior**.
- **State the schema, don't derive it** (Phase 2 §1): no parse transforms, no
  type→schema reflection.
- **Discoverability metadata lives on the `add_tool/2` map** (single source of
  truth); `instructions`, `_meta`, and the directory tool are **derived** from it —
  never a parallel store. Behavioral hints (`readOnlyHint`, …) go in `annotations`,
  not `_meta`. Namespace `_meta` keys `io.erlmcp/…`.

## Tasks (keyed to ledger rows; suggested order)

**Phase A — ergonomics.**
1. **[M2a-1]** `erlmcp_schema` builder (schema + matching validator in one place).
2. **[M2a-2]** `erlmcp:add_tool/2` data-driven map (incl. optional wayfinding keys +
   `annotations`). This map is the single source of truth (DISC-4).
3. **[M2a-3]** `erlmcp_server_handler` behaviour (`tools/0` + `handle_tool/3`); no
   `apply/3`.

**Phase B — tools surface.**
4. **[M2a-5]** `tools/call` → run handler in the M1 per-request worker.
5. **[M2a-6]** Input validation via `jesse` at the boundary; invalid → `-32602`,
   handler never runs. (Closes the "jesse declared, never used" finding.)
6. **[M2a-7]** Output schema + `structuredContent`.
7. **[M2a-8]** All five content types (text/image/audio/embedded resource/resource link).
8. **[M2a-9]** Tool `annotations` settable + surfaced in `tools/list`.
9. **[M2a-4]** `tools/list` with schemas/annotations/`_meta`, paginated (cursor/nextCursor).
10. **[M2a-10]** Runtime add/remove → `notifications/tools/list_changed`.
11. **[M2a-11]** Progress: tool worker → `erlmcp_ctx:report_progress/3` →
    `notifications/progress`.
12. **[M2a-12]** Capability map advertises `tools`/`listChanged` only when registered.

**Phase C — discoverability (DISC-1…DISC-9).** Derive `instructions`, per-tool
`_meta`, and the directory tool from the `add_tool/2` registry. Hold the
invariants: 100% metadata coverage (DISC-1), dangling-free (DISC-2) + orphan-free
(DISC-3) `next` graph, all surfaces share one source (DISC-4), namespaced keys
(DISC-5), directory excluded from conformance (DISC-6), behavioral hints in
`annotations` not `_meta` (DISC-7), non-enumerating `instructions` (DISC-8),
runtime-change consistency (DISC-9). The design doc is authoritative.

**Phase D — example & gates.**
13. **[M2a-13]** A calculator-style example exercising the whole tool surface +
    discoverability, with a CT suite.
14. **[M2a-14]** House style: no boolean params, opaque types at boundaries, no god
    module (cleanup as you write these APIs).
15. **[M2a-15]** Remove `erlmcp` (facade) + new M2a modules from `cover_excl_mods`;
    bring each to ≥90%.
16. **[M2a-16]** `rebar3 dialyzer` clean; CI green.

## Working protocol

- **Branch:** `task/0.6.0-m2a`, cut from `release/0.6.x`; PR into `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the
  closing commit.
- Raise amendments; never silently work around. Coverage (M2a-15): if a module
  can't honestly reach 90%, raise it — don't pad tests or silently re-exclude.
- Closing report: a per-row walk over all 25 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M2a (do NOT build)

Resources, prompts, logging, completion, pagination for non-tool endpoints, the
conformance scorecard — **all M2b**. Client-side anything — **M3**. New transports
— **M4**. Tasks — **M6**. Build only the tool surface + ergonomics + discoverability.

## Done when

All 25 ledger rows reach a final status; the calculator example, DISC invariants,
Dialyzer, and CI are green; the closed ledger is submitted for CDC review.
