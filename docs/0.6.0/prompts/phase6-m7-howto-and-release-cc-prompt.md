# CC Prompt — erlmcp 0.6.0, Phase 6 / Milestone P6-M7 (Howto + 0.6.0 release mechanics)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before P6-M7 closes. This milestone **ships 0.6.0**: writes the
> greenfield howto, finalizes the draft release notes / migration / checklist,
> bumps the version, tags, and publishes the GitHub release. It is the finish
> line of the Phase 6 arc that began with "no tools available."

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **P6-M7 only**: produce the
howto at `docs/creating-an-mcp-server.md`; finalize three existing draft
artifacts (`docs/0.6.0/RELEASE-NOTES-0.6.0.md`,
`docs/0.6.0/MIGRATION-0.5-to-0.6.md`, `docs/0.6.0/RELEASE-CHECKLIST.md`); run a
hand-driven **howto-following acceptance test**; bump `vsn` to `0.6.0`; verify
CI green on that commit; tag and publish. **Do not modify the spine. Do not
modify the examples.** Both are frozen; any defect surfaced at M7 is a `0.6.1`
re-entry, not in-scope work.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/phase6-m7-howto-and-release-ledger.md`** — the
   P6-M7 ledger (rows P6M7-1…P6M7-13). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **The three drafts you are finalizing, not creating from scratch**:
   - `docs/0.6.0/RELEASE-NOTES-0.6.0.md`
   - `docs/0.6.0/MIGRATION-0.5-to-0.6.md`
   - `docs/0.6.0/RELEASE-CHECKLIST.md`
   Read each in full before editing. The bones are there; your job is to
   finish, polish, and ground in the closed milestones' real content.
4. **`docs/0.6.0/planning/phase6-unified-transport-architecture.md` §10** —
   the howto idea, the canonical greenfield tutorial framing.
5. **The closed milestone ledgers** (M1 / M2 / M3 / M4 / M5 / M6) — the source
   of truth for what 0.6.0 actually shipped. The release notes claim *only*
   what the ledgers' evidence supports.
6. **`CLAUDE.md`** — especially *Never loosen a check to make it pass*, the
   *No hand-maintained `CHANGELOG`* rule (the release notes ARE the changelog),
   and the *0.5.0 API is not preserved* line that drives the migration guide's
   tone. **House style:** `priv/ai/erlang/SKILL.md` first.
7. **The M6 examples + their READMEs** — the howto's worked example will lean
   on `examples/simple/` (lightest); the discoverability and validation
   sections will reference all three.

## Locked decisions (non-negotiable)

- JSON via `jsx` inside `erlmcp_codec` only.
- Schema validator = `jesse` (M5 — exercised here, not changed).
- Min OTP 25+. Dialyzer is gated to OTP 27+ — run `make dialyzer` on **27 and
  28** on the version-bump commit.
- Coverage 90% per-module, scoped via `cover_excl_mods`; no new exclusions in
  M7 (the spine doesn't change, so coverage doesn't either).
- **Never loosen a check to reach green** — no suppressions, no widened specs,
  no skipped tests. *Especially at the finish line.* The risk profile of
  *"it's the last milestone, just suppress this one warning"* is exactly what
  the rule exists to prevent.
- **No `CHANGELOG` file.** Release notes + git history + GitHub release are the
  record.

## The two scope rules — internalise both first

**Rule 1: Do not modify the spine.** `src/erlmcp_*.erl` is frozen for M7. If
something is wrong with it that the howto-following acceptance surfaces, the
fix is a `0.6.1` row — not a M7 row. Tagging a release while quietly mutating
the spine undermines the verification chain that says *the ledgers describe
what shipped*. *Escalate-not-decide*; we have learned this three times now (M4
sampling, M5 schema, M6 spine-freeze).

**Rule 2: Do not modify the examples.** `examples/*/` is frozen for M7.
Examples are the worked-example backbone of the howto; rewriting them at the
finish line would invalidate M6's acceptance verdict. If the howto's
walkthrough wants to do something the examples don't, the howto adapts; the
examples don't.

**Diff size for M7 should be measured in:**

- **Spine code** (`src/erlmcp_*.erl`): **zero lines**.
- **Example code** (`examples/*/`): **zero lines**.
- **Version bump** (`src/erlmcp.app.src`): **one line** (`{vsn, "0.5.1"}` → `{vsn, "0.6.0"}`).
- **Howto** (`docs/creating-an-mcp-server.md`): substantive — this is a new
  file.
- **Finalized drafts** (`docs/0.6.0/RELEASE-NOTES-0.6.0.md`,
  `MIGRATION-0.5-to-0.6.md`, `RELEASE-CHECKLIST.md`): substantive — these grow
  from draft to final.
- **Acceptance doc** (`docs/0.6.0/acceptance/phase6-howto-acceptance.md`): new
  file documenting the howto-following test.

If you find yourself opening `src/erlmcp_*.erl` or `examples/*/src/*.erl` —
**stop and escalate**. That is not M7.

## Tasks (each maps to ledger rows; suggested build order)

**Phase A — the howto (the substantive new artifact).**

1. **[P6M7-1]** Draft `docs/creating-an-mcp-server.md` as a step-by-step
   greenfield tutorial. Suggested structure:
   - "What you'll build" — one paragraph + a screenshot/quote of the end state.
   - "Prerequisites" — OTP 25+, rebar3, optional Claude Desktop.
   - "Hello world" — a minimal server using the `simple` example's shape as
     the template, but built up step-by-step in the howto rather than dropped
     in whole.
   - "Adding tools / resources / prompts" — the M3 wayfinding fields
     (`category`, `when_to_use`, `entry_point`, `next`) explained as you add
     them.
   - "Making your server discoverable" → P6M7-2.
   - "Validation at the edge" → P6M7-3.
   - "Connecting to Claude Desktop" — the JSON config, mapping to the M6
     pattern.
   - "Where to go next" — pointers to the M6 examples for more advanced
     features (handler behaviour, structured output, tasks/progress, sampling,
     resource templates with completion).

   **Copy-pasteable code blocks.** Every step the user is expected to perform
   has a verbatim block they can paste. The howto-following acceptance test
   (P6M7-7) is the verification that the blocks are correct.

2. **[P6M7-2]** Write the **"Make your server discoverable"** section. Walks
   through: configuring the identity block, declaring `protocol_features` on
   tools that genuinely exercise the named feature (honest declarations —
   carry the M6 rule forward), writing a model-facing README. Cross-references
   the M6 examples by file path and the M3 discoverability plan.

3. **[P6M7-3]** Write the **"Validation at the edge"** section. Covers: the
   inbound jesse seam (envelope → -32600, params → -32602), the outbound
   fail-closed seam (-32603), the SHOULD⇒MUST overlay rationale (handoff §1.3
   Icon shape / §1.5 `taskSupport` enum / §1.4 UTF-8 — *why those three bugs
   can't recur*), and the *validate-at-edge, crash-in-interior* idiom.
   References M5. The bug-rationale paragraph explicitly names the three
   bugs — this section's job is to prevent future contributors reinventing
   them.

**Phase B — finalize the drafts.**

4. **[P6M7-4]** Finalize `docs/0.6.0/RELEASE-NOTES-0.6.0.md`. Read the draft
   first. Then ground each claim in the ledgers' evidence: M1 (unified
   spine), M2 (stdio rebuild + OTP launcher), M3 (discoverability machinery),
   M4 (Streamable HTTP via Cowboy), M5 (strict validation), M6 (examples +
   Claude Desktop acceptance), M7 (this milestone). **Honest sections**:
   *Shipped*, *Deferred to 0.6.x*, *Out-of-scope for 0.6.0*. No
   `TODO` / `TBD` / `<placeholder>` markers may remain. Don't over-claim.

5. **[P6M7-5]** Finalize `docs/0.6.0/MIGRATION-0.5-to-0.6.md`. Read the draft
   first. The 0.5.0 API is not preserved (per `CLAUDE.md`), so this is a real
   migration. Concrete before/after code snippets for the major API surface
   deltas: how to start a server (`erlmcp:start_stdio_setup` vs the old
   shape), how to register tools/resources/prompts, where wayfinding fields
   land, where validation lives, how transports are wired. The bar: a 0.5.x
   user can port their server to 0.6.0 by reading only this guide.

6. **[P6M7-6]** Finalize `docs/0.6.0/RELEASE-CHECKLIST.md`. This is the
   **gating sequence** for the one-way operations (tag + publish). Walk it
   item by item; each item gets a checked state with evidence (commit SHA / CI
   link / version-bump diff / tag SHA / GitHub release URL). **Do not skip
   ahead in the sequence.** The checklist is *where the order is enforced*.

**Phase C — acceptance.**

7. **[P6M7-7]** Create `docs/0.6.0/acceptance/phase6-howto-acceptance.md`. The
   procedure: **a fresh checkout** (clean rebar3 state, no prior build
   artifacts) plus **literal step-by-step execution** of the howto. Document
   the steps, the observed state at each step, and the final verdict. The
   verdict must be **pass** for P6M7-1 to close; a `partial` or `fail` means
   the howto isn't done — go back to Phase A, fix the howto, run the
   acceptance again. This is the final acceptance of the Phase 6 arc.

   **Time-box** to one focused session. If a defect surfaces in the spine or
   examples during the test, file a `0.6.1` follow-up — *do not* fix it in
   M7 (the scope rules forbid it). The howto either describes what shipped or
   it doesn't; that's the test.

**Phase D — release mechanics (the one-way doors).**

8. **[P6M7-8]** Bump `src/erlmcp.app.src` `vsn` from `0.5.1` to `0.6.0`. One
   commit, message `release: 0.6.0`. The bump and the tag will be at the
   same commit.

9. **[P6M7-11 / P6M7-12]** Verify gates green on the bump commit: `make
   check` exits 0, dialyzer clean on 27 and 28, no new suppressions, no new
   `cover_excl_mods` entries.

10. **[P6M7-9]** After CI is green on the bump commit on `release/0.6.x`,
    create the tag: `git tag 0.6.0 <commit>`, `git push origin 0.6.0`.
    **CI-green-before-tag is non-negotiable.** Tagging a red commit is a
    permanent public record of disorder.

11. **[P6M7-10]** Create the GitHub release at the `0.6.0` tag. Body sourced
    from `docs/0.6.0/RELEASE-NOTES-0.6.0.md`. Marked **Latest**. Verify the
    rendered body before publishing.

**Phase E — close.**

12. **[P6M7-13]** Walk the ledger. Per-row dispositions. Tally to 13.

## Working protocol

- **Branch:** `task/0.6.0-p6m7`, cut from `release/0.6.x` **after P6-M6 merges**;
  PR back into `release/0.6.x`; merge to `release/0.6.x`; then tag on
  `release/0.6.x` at the merge commit (not on the task branch).
- **Commit per phase** (howto → finalized notes → finalized migration → walked
  checklist → acceptance doc → version bump → tag → release). The version-bump
  commit is its own focused commit with no other content.
- **Raise, don't route around.** Acceptance surfaces a defect → file a `0.6.1`
  follow-up and *document* it; *do not* fix it in M7. CI red on the bump
  commit → fix, never tag. Draft artifact fundamentally wrong → escalate; do
  not silently rewrite past the intent of the original draft.
- **Closing report:** **per-row walk over all 13 rows.** No prose summary. Name
  uncertainty. **Count the actual rows in the ledger file** before declaring
  the walk complete — recurring lesson.
- **Iteration cap: 5.**
- **Subagents for lookup only.**

## Out of scope for P6-M7 (do NOT build)

- **Touching the spine** (`src/erlmcp_*.erl`). Scope rule 1.
- **Touching the examples** (`examples/*/`). Scope rule 2.
- **Per-tool `inputSchema` validation on `tools/call`** — carry-forward to
  `0.6.1`.
- **A hand-maintained `CHANGELOG` file** — explicitly forbidden by `CLAUDE.md`.
  The release notes are the changelog.
- **0.7+ features** (new transports, new SDK surface, the graph-RAG extension
  Duncan has queued as the first 0.6.x extension).
- **Re-running M1–M6 acceptance.** Each milestone closed against its own
  acceptance; you don't re-litigate them. M7's acceptance is the howto's.
- **Polishing M6 follow-ups.** If M6 left documented carry-forward items, they
  belong to `0.6.1`, not M7.

## Done when

The howto exists and is copy-pasteable; both teaching sections (discoverability,
validation-at-edge) land in it; the three draft artifacts are finalized with no
placeholder markers; the howto-following acceptance test passes on a fresh
checkout; `src/erlmcp.app.src` shows `vsn` `0.6.0`; CI is green on the bump
commit; the `0.6.0` tag is pushed; the GitHub release is published as **Latest**
with the release-notes body; the ledger walks to 13. **Then 0.6.0 is shipped,
the Phase 6 arc closes against the bug it began with, and the path to 0.6.1 is
the queued graph-RAG extension.**
