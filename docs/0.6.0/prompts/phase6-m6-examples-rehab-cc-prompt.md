# CC Prompt — erlmcp 0.6.0, Phase 6 / Milestone P6-M6 (Examples rehab + Claude Desktop acceptance)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before P6-M6 closes. This milestone is the **consumer-side payoff** of
> M3 (discoverability machinery) + M5 (validation seam) — the example servers
> populate the content that flows through both, and the original "no tools
> available" arc closes against a documented Claude Desktop acceptance test.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **P6-M6 only**: populate the
identity block and `protocol_features` field in each example server, rewrite
each example's README so the model-facing reader gets useful orientation,
confirm the original payload-shape bugs structurally cannot recur (M5 catches
them; M6 ensures the examples don't trip them), keep the gates green, and run a
**documented hand-driven Claude Desktop acceptance test** for each example. The
howto (P6-M7) and the 0.6.0 release tag (P6-M7) are not your concern.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/phase6-m6-examples-rehab-ledger.md`** — the P6-M6
   ledger (rows P6M6-1…P6M6-12). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`docs/0.6.0/planning/phase6-unified-transport-architecture.md`** — re-read
   §6 to see how M6 sits *after* the spine, not in it. The spine is frozen for
   M6.
4. **`docs/0.6.0/planning/phase6-discoverability-plan.md`** — the discoverability
   plan §2A–§2D, particularly how the identity block flows into the generated
   `instructions` and the `directory` tool.
5. **`docs/0.6.0/milestones/phase6-m3-discoverability-ledger.md`** and
   **`docs/0.6.0/milestones/phase6-m5-strict-validation-ledger.md`** — the
   machinery you are *applying* lives in M3; the validator you are *passing under*
   lives in M5. Both are closed; M6 doesn't modify either.
6. **`workbench/2026-05-25-cdc-handoff.md` §1.3 / §1.5** — the Icon shape and
   `taskSupport` enum bugs that started the whole arc. P6M6-5 ensures the
   examples don't reintroduce them.
7. **`CLAUDE.md`** — especially *Never loosen a check to make it pass* and the
   coverage rule. **House style:** `priv/ai/erlang/SKILL.md` first
   (`11-anti-patterns.md`, then `03-error-handling.md` and `04-data-and-types.md`
   for the example handler patterns).

## Locked decisions (non-negotiable)

- JSON via `jsx` inside `erlmcp_codec` only.
- Schema validator = `jesse` (M5 — exercised here, not changed).
- Min OTP 25+. Dialyzer is gated to OTP 27+ — run `make compile-examples` and
  per-profile dialyzer on **27 and 28**.
- Coverage 90% per-module, scoped via `cover_excl_mods`; **no new exclusions**
  for example modules without a per-line named-ceiling amendment.
- Validate at the edge; **crash in the interior**; translate at the boundary.
- **Never loosen a check to reach green** — no suppressions, no widened specs,
  no skipped tests. Escalate, don't loosen.
- **Do not modify the spine.** The unified transport / session / responder seam
  (`erlmcp_server`, `erlmcp_server_session`, `erlmcp_reply`, `erlmcp_codec`,
  `erlmcp_instructions`, `erlmcp_schema`) is **frozen for M6**. If a P6-M6
  criterion seems to need a spine change, **escalate** — that's a sign M3 or M5
  has a gap that needs to land before M6 closes, not a sign M6 should grow scope.

## The scope rule — internalise this first

This is an **application** milestone, not a **library** milestone. The library
work — the machinery (M3), the validator (M5) — is done. M6 takes the example
servers as-they-are on the unified spine and **populates the content** that
flows through the machinery and passes under the validator. The diff size for
M6 should be measured in:

- **Library code** (`src/`): **zero lines**, with the possible exception of a
  documented escalation-and-amendment if a true spine gap is discovered.
- **Example code** (`examples/*/src/`): small per file — adding identity to the
  `start/1` config, adding `protocol_features` to a handful of tool specs,
  light refactoring of helper builders.
- **READMEs** (`examples/*/README.md`): substantive — these grow new
  model-facing sections.
- **Tests** (`test/`): per-example CT suites assert the identity + features
  flow through correctly.
- **Acceptance doc** (`docs/0.6.0/acceptance/phase6-claude-desktop-acceptance.md`):
  new file documenting the hand-driven test procedure + observed state.

If you find yourself opening files under `src/erlmcp_*.erl` — **stop and
escalate**. That is *not* what M6 does. The recurring lesson from M5: *"escalate
≠ defer"* — escalation means stop and tell CDC/Duncan, not decide and amend.

## Tasks (each maps to ledger rows; suggested build order)

**Phase A — populate the content (the bulk of M6).**

1. **[P6M6-1]** Add an `identity` map to each example's `start/1` config —
   `name`, `purpose` (one-paragraph what-this-is-for, model-facing), `version`
   (matches the app.src), `source` (the actual GitHub URL), optional `docs`.
   Three sites: `examples/simple/src/simple_server.erl`,
   `examples/calculator/src/calculator_server.erl`,
   `examples/weather/src/weather_server.erl`.
2. **[P6M6-2]** Add `protocol_features` to the tool specs that genuinely
   exercise the named feature:
   - calculator's `slow_compute` → `[tasks, progress]` (the handler already
     calls `erlmcp_ctx:report_progress`).
   - calculator's `explain` → `[sampling]` (the handler calls `request_peer`).
   - weather's resource template → `[completion]` (the template carries
     `completions`).
   Do **not** declare features on tools that don't exercise them. A
   `[sampling]` claim is a promise the handler actually performs sampling —
   honest declarations only.
3. **[P6M6-3]** Add CT `erlmcp_example_*_SUITE:instructions_readable` per
   example: drive `initialize`, assert the returned `<<"instructions">>` binary
   contains the server `name`, the configured `purpose`, the `directory`
   pointer, and a "protocol features" line for tools that declare them.
   - If an example's generated `instructions` *doesn't* read well without an
     author override, that's a M3 machinery gap — **stop and escalate**, don't
     paper over with a hand-written `instructions` binary on the example.

**Phase B — README rewrites.**

4. **[P6M6-4]** Each example README grows two model-facing sections (the
   developer sections stay):
   - **Identity** (or **What this server is for**) — matches the configured
     `purpose`. One paragraph.
   - **Tool orientation** — matches the `directory` tool's category structure;
     points the model at entry-point tools and the `next` chains.

   Keep the existing dev-facing content (Run, Claude Desktop config, Tests).
   The split is: *developer reads to install; model reads to use*. M6 adds the
   second.

**Phase C — original-bug closure.**

5. **[P6M6-5]** Confirm the calculator's `emoji_icon/1` helper produces a
   P6M5-6-conformant Icon (`src` data-URI, `additionalProperties: false`
   honoured); confirm no example uses the buggy `#{type=>emoji,emoji=>...}`
   shape; confirm no example uses `taskSupport => allowed`. The greps in the
   ledger's Verify cell must return clean. The CT covering `tools/list` on each
   example must pass under M5's outbound validator with no `-32603` on the
   wire.

**Phase D — gates.**

6. **[P6M6-6 / P6M6-8 / P6M6-9 / P6M6-10 / P6M6-11]** Standard close: `make
   compile-examples` green; `make check` green; coverage ≥90% per-module on
   example modules; dialyzer clean on 27 *and* 28 across example profiles;
   CI green on `task/0.6.0-p6m6`.

**Phase E — Claude Desktop acceptance (the closing of the original arc).**

7. **[P6M6-7]** Create
   `docs/0.6.0/acceptance/phase6-claude-desktop-acceptance.md`. For **each**
   example:
   - **Procedure** — verbatim Claude Desktop config (the one from the README),
     the steps the human performs, and the prompts they enter.
   - **Observed state** — model output captures, screenshots if relevant, the
     CD log lines that confirm `initialize` / `tools/list` / `directory` /
     tool-call. For calculator's `slow_compute`: confirm progress notifications
     surface to the model. For calculator's `explain`: confirm the sampling
     round-trip works.
   - **Verdict** — one of **pass**, **partial**, **fail**, with a one-line
     reason.
   - **Follow-ups** — any defect found gets a tracked follow-up (a GH issue or
     a documented note in the acceptance doc itself with a re-entry milestone).
     **Do not** soft-pass — a `partial` or `fail` is a real disposition, not a
     reason to spin.

   **Pre-condition CD was tracking from M3** — does Claude Desktop actually
   surface `InitializeResult.instructions` to the model? — is **answered here**.
   Whichever it is, document it. If CD doesn't surface `instructions`, the
   `directory` tool is doing the orientation work; that's still a pass for M6's
   purposes as long as the model gets a clean orientation through *some* surface.

   **Time-box** the acceptance work to **one focused session per example.** If
   a defect surfaces that's non-trivial to fix on the spine, file the follow-up
   and ship M6 with the defect documented — *don't* roll spine work into M6.

## Working protocol

- **Branch:** `task/0.6.0-p6m6`, cut from `release/0.6.x` **after P6-M5 merges**;
  PR back into `release/0.6.x`.
- **Commit per phase** (content → READMEs → bug-closure verify → gates →
  acceptance doc); update Status/Evidence per row in the closing commit.
- **Raise, don't route around.** Spine gap discovered while populating an
  example → escalate with `file:line` and what the gap is. CD acceptance
  surfaces a real defect → escalate; the *fix* is a P6-M7 prerequisite (or a
  later milestone), the *document* is a P6-M6 row.
- **Closing report:** **per-row walk over all 12 rows.** No prose summary. Name
  uncertainty. **Count the actual rows in the ledger file** before declaring the
  walk complete — recurring lesson.
- **Iteration cap: 5.**
- **Subagents for lookup only.**

## Out of scope for P6-M6 (do NOT build)

- **Touching the spine** (`src/erlmcp_*.erl` — the server, session, codec,
  schema, instructions, reply, transport modules). If a P6-M6 criterion seems
  to need it, **escalate** — that surfaces a gap in M3 or M5 that has to land
  before M6 closes, not a license to grow M6's diff.
- **Modifying M3 / M5 ledger rows.** Both milestones are closed. If acceptance
  reveals a gap, that's a *new* row on a *new* milestone (P6-M7 prereq), not a
  retroactive amendment.
- **Per-tool `inputSchema` validation on `tools/call`** — distinct from the
  protocol-schema validation M5 wired. Carry-forward to P6-M7 or its own
  follow-up.
- **The howto / "make your server discoverable" teaching content** — that's
  P6-M7's job.
- **Release tag / version bump / release notes for 0.6.0** — P6-M7.
- **New transports, new server features, new SDK surface** — out of scope for
  the 0.6.0 arc entirely; 0.7+.

## Done when

All 12 ledger rows have a final Status + Evidence; every example server has an
identity block and the correct `protocol_features` declarations; every example
README has the model-facing identity + orientation sections; the original
payload-shape bugs cannot recur in the examples (greps clean); `make
compile-examples` and `make check` green; coverage ≥90% per-module on example
modules (or a named-ceiling amendment); dialyzer clean on 27 and 28 across the
example profiles; the Claude Desktop acceptance doc exists with a per-example
verdict; CI green on `task/0.6.0-p6m6`. **Then the original "no tools available"
arc closes against a documented test, and 0.6.0 is one milestone away from
shippable.**
