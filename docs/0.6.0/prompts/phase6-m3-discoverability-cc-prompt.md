# CC Prompt — erlmcp 0.6.0, Phase 6 / Milestone P6-M3 (Discoverability enhancement)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before P6-M3 closes. This milestone is **library machinery only**:
> example content is P6-M6, the howto is P6-M7. Do not write example identity
> values, do not rewrite READMEs, do not start on a howto section.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **P6-M3 only**: enrich the
already-wired discoverability layer to **README-grade on first contact**. The
spec-blessed slot (`InitializeResult.instructions`) is **already populated** —
the work is enriching its *content* and adding the supporting machinery (the
`directory` tool's server-identity block, a first-class `protocol_features` field,
author-supplied override). Not wiring; *enriching*.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/phase6-m3-discoverability-ledger.md`** — the P6-M3
   ledger (rows P6M3-1…P6M3-11). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`docs/0.6.0/planning/phase6-discoverability-plan.md`** — the plan,
   reconciled with server-side state. Read §0 (what's wired vs what's gap) and §2
   (prioritized actions A–E) before touching code.
4. **`workbench/erlmcp-discoverability-assessment.md`** — CD's consumer-side
   first-contact report. Useful context for *why* this work exists.
5. **`CLAUDE.md`** — especially *Never loosen a check to make it pass* and the
   coverage rule. **House style:** `priv/ai/erlang/SKILL.md` first
   (`11-anti-patterns.md`, then `02-api-design.md`, `04-data-and-types.md`).

## Locked decisions (non-negotiable)

- JSON via `jsx` inside `erlmcp_codec` only; `jesse` at the edge (not exercised here).
- Min OTP 25+. Dialyzer is gated to OTP 27+ — run `make dialyzer` on **27 and 28**.
- Coverage 90% per-module, scoped via `cover_excl_mods`; **settle the M3 scope in
  your first commit** (P6M3-9), no new exclusions.
- Validate at the edge, crash in the interior. Opaque types + accessors.
- **Never loosen a check to reach green** — no suppressions, no widened specs to
  silence dialyzer, no skipped tests. Escalate, don't loosen.

## Context — what's already wired (don't re-do)

Verified before this brief was written:
- `erlmcp_server_session` populates `<<"instructions">>` on `initialize`
  (`Instructions = erlmcp_instructions:generate(maps:values(Tools))`, lines
  ~328/338). **Don't re-wire the slot — enrich what flows through it.**
- `erlmcp_instructions:generate/1` exists but emits a one-sentence stub. The
  current full output is verbatim: *"This server provides tools organized by
  category. Categories: arithmetic, demo. Start with: add. Use tools/list for
  the full catalog."* (also note: it says "Use tools/list" — your P6M3-7
  quick-win flips this to point at `directory`).
- `erlmcp:make_directory_tool/0` exists; the tool produces a categorized listing
  but has no server-identity block.
- Per-tool `category` / `when_to_use` / `next` / `entry_point` are already
  accepted (example: `calculator_server.erl`); `protocol_features` is **not** yet
  a recognized field — you add it.

## Tasks (each maps to ledger rows; suggested build order is bottom-up)

**Phase A — data model.**
1. **[P6M3-5]** Add `protocol_features => [atom()]` as a first-class field on
   tool / resource / prompt specs in `erlmcp_server`'s registration validators
   (validate-at-edge: type-checked when present, optional). Surface it in
   `tools/list` `_meta`.
2. Accept new server-identity keys in the server's start `Config`:
   `purpose`, `source` (in addition to existing `name`/`version`). Store them
   on the server (`erlmcp_server` state) and expose via a getter.
3. **[P6M3-2]** Accept an optional `instructions => binary()` in the server's
   start `Config` (author override).

**Phase B — `directory` tool enrichment.**
4. **[P6M3-4]** Add a top-level **server identity block** to `directory`'s
   output: `name`, `purpose`, `version`, `source`, `protocol_features`, `docs`
   (optional URL). Read from the server's state/config.
5. Include each tool's `protocol_features` in the per-tool entry inside `directory`'s
   output.

**Phase C — `instructions` generator enrichment.**
6. **[P6M3-1]** Rework `erlmcp_instructions:generate/_` to take richer inputs
   (server identity + tools with `protocol_features`) and emit a multi-line,
   README-grade string: server identity, category overview, entry points,
   **protocol features exercised**, and the **pointer to `directory`**. Keep
   the function pure (testable without the session).
7. **[P6M3-2]** In the session, if the server config supplies `instructions`,
   use it verbatim and skip the generator. Otherwise call the (enriched) generator.
8. **[P6M3-7]** Quick-win is now folded in: the new generator points at
   `directory`, not `tools/list`.

**Phase D — `directory` description + the easy polish.**
9. **[P6M3-6]** Rewrite the `directory` tool's own description in
   `erlmcp:make_directory_tool/0` to start with unmissable orientation language:
   "Start here — an oriented overview of this server, with workflow hints and
   which tools use advanced protocol features."

**Phase E — tests & gates.**
10. **[P6M3-3]** CT in `erlmcp_server_session_SUITE`: an `initialize` over a
    configured server returns instructions matching what `generate/_` would
    produce; for the override path, returns the supplied binary verbatim.
11. **[P6M3-8]** Keep `make check` green; **[P6M3-9]** coverage gate passes with
    `erlmcp_instructions` and `erlmcp` (directory helpers) ≥90% each;
    **[P6M3-10]** `make dialyzer` clean on 27 and 28 with **zero suppressions**;
    **[P6M3-11]** CI green on `task/0.6.0-p6m3`.

## Working protocol

- **Branch:** `task/0.6.0-p6m3`, cut from `release/0.6.x` **after P6-M2 merges**;
  PR back into `release/0.6.x`.
- **Commit per coherent group** (data model → directory → generator → description
  → tests); update Status/Evidence per row in the closing commit.
- **Raise, don't route around.** Wrong/impossible criterion → amendment with
  re-entry. Dialyzer warning that looks wrong → escalate `file:line`; never loosen.
- **Closing report:** **per-row walk over all 11 rows.** No prose summary. Name
  uncertainty. (Recurring lesson: enumerate the *actual* row count from the ledger
  file — don't stop at 16 if it has 18; don't stop at 11 if it has 12.)
- **Iteration cap: 5.**
- **Subagents for lookup only.**

## Out of scope for P6-M3 (do NOT build)

- **Example content** — populating `purpose`/`source`/`protocol_features` values
  on the example servers (`simple`/`calculator`/`weather`) is **P6-M6**. Your job
  is the *machinery* that accepts and surfaces those fields, not the values.
- **Example READMEs** clarifying the three-server relationship — **P6-M6**.
- The **"make your server discoverable" howto section** — **P6-M7**.
- HTTP/Cowboy — **P6-M4**. jesse/MCP-schema payload validation — **P6-M5**.
- Any consumer-side question (does Claude Desktop surface `instructions`?). That
  is CD's verification, in parallel; it doesn't gate your work, only sizes its
  payoff.

## Done when

All 11 ledger rows have a final Status + Evidence; `erlmcp_instructions:generate`
produces README-grade output from richer inputs; the author-supplied override is
honored; `directory`'s output carries a server identity block + per-tool
`protocol_features`; `directory`'s own description starts with "Start here";
`make check` green; dialyzer clean on 27/28 with zero suppressions; CI green;
the closed ledger is submitted for CDC review.
