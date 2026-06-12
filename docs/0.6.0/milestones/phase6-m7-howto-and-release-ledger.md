# Phase 6, Milestone P6-M7: Howto + 0.6.0 release mechanics

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state — running each Verify command and reading diffs, not
> summaries. No milestone advances until the ledger is fully closed.

**Goal (Phase 6 §6, P6-M7):** ship 0.6.0. This is the **finishing milestone** of
the Phase 6 arc — write the **greenfield howto** at
`docs/creating-an-mcp-server.md` (the document that teaches a new user to build
an MCP server end-to-end on the 0.6.0 spine, exercising M3's discoverability
machinery and M5's validation seam); finalize the **draft release notes**
already on disk at `docs/0.6.0/RELEASE-NOTES-0.6.0.md`; finalize the **draft
migration guide** at `docs/0.6.0/MIGRATION-0.5-to-0.6.md`; walk the **draft
release checklist** at `docs/0.6.0/RELEASE-CHECKLIST.md`; bump the version in
`src/erlmcp.app.src` from `0.5.1` to `0.6.0`; verify CI green on the tag commit;
**tag and publish 0.6.0**.

Per `CLAUDE.md`: SemVer + published GitHub release notes + git history is the
release record. **No hand-maintained `CHANGELOG`** — the release notes ARE the
changelog. The published GitHub release body points at
`RELEASE-NOTES-0.6.0.md`.

**Locked decisions (carried):** JSON via `jsx` behind `erlmcp_codec` only;
`jesse` at the edge (M5); min OTP 25+; coverage 90% per-module scoped via
`cover_excl_mods`; opaque types + accessors, no shared records; one way to do a
thing, no `_new` forks. **Never loosen a check to make it pass** (`CLAUDE.md`):
no suppressions, no widened specs, no skipped tests — escalate instead. Dialyzer
gated to OTP 27+ (`make dialyzer`); run on **27 and 28**.

**Scope discipline:** **Do not modify the spine** and **do not modify the
examples**. Both are frozen at M7. If the howto-following acceptance (P6M7-7)
surfaces a defect in either, that's a `0.6.1` re-entry — *not* a reason to grow
M7's diff. The point of M7 is to ship what M1–M6 built; mutating it at the
finish line undermines the verification chain. *Escalate-not-decide*; we have
learned this rule three times now (M4 sampling, M5 schema, M6 spine-freeze).

**One-way doors:** `git tag 0.6.0` and the published GitHub release are
**one-way operations**. The order matters: tag only after CI is green on the
exact commit; publish the GitHub release only after the tag is pushed. The
checklist (P6M7-6) is the gating sequence — walk it, don't shortcut it.

**Branch:** `task/0.6.0-p6m7`, cut from `release/0.6.x` **after P6-M6 merges**.
PR back into `release/0.6.x`; merge to `release/0.6.x`; **then** tag at the
merge commit on `release/0.6.x` (not on the task branch). All Verify commands
run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| P6M7-1 | A new file `docs/creating-an-mcp-server.md` is a **greenfield howto** that walks a user from zero to a running MCP server on the 0.6.0 spine. The walkthrough uses one of the M6 examples (recommend `simple`) as the running example; each step is **copy-pasteable**; the final state is a server that initialize/tools/list/tools/call cleanly under Claude Desktop. | The file exists; following it literally on a fresh checkout produces a working server (this is the P6M7-7 acceptance test). | serious | Phase 6 §6 P6-M7; architecture doc §10 ("the howto idea") | open | | The teaching artifact for 0.6.0. Lean on the M6 examples — don't re-invent them. |
| P6M7-2 | The howto includes a **"Make your server discoverable"** section that teaches: configuring the identity block, declaring `protocol_features` on tools that exercise advanced protocol features, writing a model-facing README. Cross-references the M6 examples and the M3 discoverability plan. | The section exists in `docs/creating-an-mcp-server.md`; the worked example matches the M6 example servers' shape. | serious | Phase 6 §6 P6-M7; P6-M3 carry-forward | open | | The user-side framing of M3. *"Here's how to make your server good at first contact with a model."* |
| P6M7-3 | The howto includes a **"Validation at the edge"** section that teaches: the inbound jesse validation seam (-32600 / -32602), the outbound fail-closed seam (-32603), the SHOULD⇒MUST overlay rationale (handoff §1.3 / §1.5 / §1.4 → why those bugs can't recur), and the *validate-at-edge, crash-in-interior* idiom. References M5. | The section exists in `docs/creating-an-mcp-server.md`; the overlay-rationale paragraph explicitly names the three bugs that drove it. | serious | Phase 6 §6 P6-M7; P6-M5 carry-forward | open | | The user-side framing of M5. The "why" matters: this is the section that prevents future contributors reinventing one of the three original bugs. |
| P6M7-4 | The **draft release notes** at `docs/0.6.0/RELEASE-NOTES-0.6.0.md` are **finalized** — a substantive walk through what changed in 0.6.0: unified transport (M1/M2/M4), discoverability machinery (M3), strict validation (M5), examples + Claude Desktop acceptance (M6), the howto + release mechanics (M7), and a "thanks to" section if applicable. The notes are honest — they distinguish *shipped*, *deferred to 0.6.x*, and *out-of-scope-for-0.6.0*. | The file is updated past its current draft state; no `TODO` / `TBD` / `<placeholder>` markers remain; the notes accurately reflect the closed milestones' content (CDC spot-checks against ledger evidence). | serious | `CLAUDE.md` (release notes ARE the changelog) | open | | Tell the truth, don't oversell. Over-claiming in release notes is a calibration failure that costs trust. |
| P6M7-5 | The **draft migration guide** at `docs/0.6.0/MIGRATION-0.5-to-0.6.md` is **finalized** — what 0.5.x users need to do to move to 0.6.0. The 0.5.0 API was not preserved (per `CLAUDE.md`: *"Break freely; the 0.5.0 API is not preserved"*), so this is a real migration, not a deprecation list. | The file is updated past its current draft state; no `TODO` / `TBD` / `<placeholder>` markers remain; concrete before/after code snippets for the major API surface deltas. | serious | `CLAUDE.md` (0.5.0 API not preserved) | open | | If a 0.5.x user can't, after reading this, port their server to 0.6.0 without reading source, the guide isn't done. |
| P6M7-6 | The **draft release checklist** at `docs/0.6.0/RELEASE-CHECKLIST.md` is finalized and **walked**: each item has a checked-and-dated state in the file, with evidence (commit SHA / CI link / version-bump diff / tag SHA / GitHub release URL). The checklist is the **gating sequence** for the one-way operations (P6M7-9 / P6M7-10). | The file shows every item resolved with evidence; the order of operations matches the file's documented sequence. | serious | One-way-door discipline | open | | The checklist is where the *order* is enforced. Don't skip ahead. |
| P6M7-7 | **Howto-following acceptance test**: a fresh checkout (clean rebar3 state, no prior build artifacts) plus literal step-by-step execution of `docs/creating-an-mcp-server.md` produces a server that initializes cleanly under Claude Desktop, surfaces tools, and responds correctly to at least one `tools/call`. The procedure and observed state are documented in `docs/0.6.0/acceptance/phase6-howto-acceptance.md`. | The acceptance doc exists; the verdict is **pass** (a `partial` / `fail` is a P6M7-1 row failure — the howto isn't done). | serious | Phase 6 §6 P6-M7; the closing of the original arc as *teachable knowledge* | open | | This is the final acceptance of the Phase 6 arc. The original bug was *"no tools available."* The closing is *"following the published howto produces tools available."* One focused session. |
| P6M7-8 | **Version bump**: `src/erlmcp.app.src` `vsn` field is updated from `0.5.1` to `0.6.0`. The bump is in **a single, clean commit** with a conventional commit message (e.g. `release: 0.6.0`). | `grep -nE '\{vsn,\s*"0\.6\.0"\}' src/erlmcp.app.src` returns one match; `git log --oneline` shows the version-bump commit. | serious | SemVer | open | | The version bump and the tag should be at the same commit, not adjacent commits. |
| P6M7-9 | **Tag**: `git tag 0.6.0` is created at the version-bump commit on `release/0.6.x` after CI green on that exact commit. Tag is pushed. | `git rev-parse 0.6.0` returns the version-bump commit SHA; CI on the tag commit is green; `git ls-remote --tags origin 0.6.0` confirms the tag is on the remote. | serious | One-way-door release mechanics | open | | The CI-green-before-tag order is non-negotiable. Tagging a red commit is a permanent public artifact of disorder. |
| P6M7-10 | **GitHub release published**: a GitHub release at the `0.6.0` tag is created with the body sourced from `docs/0.6.0/RELEASE-NOTES-0.6.0.md`. Marked as the latest release. | The GH release URL exists and is reachable; the body matches the release notes; the release is marked **Latest**. | serious | `CLAUDE.md` (published release notes are the changelog) | open | | This is the second one-way operation. Verify the body renders cleanly before publishing. |
| P6M7-11 | **No regression** on M1–M6: `make check` exits 0 on the version-bump commit; all suites pass; coverage gate intact; dialyzer clean on 27 and 28. | `make check` green on the tag commit; CI green across OTP 25–28 on that exact commit. | serious | DoD | open | | The same gate as every prior milestone, applied at the tag commit. |
| P6M7-12 | **No checks weakened** anywhere in M7: no new `nowarn` / `-dialyzer(...)` attributes, no `cover_excl_mods` additions, no skipped tests, no widened specs. The version bump and tag don't touch source-correctness gates. | `! grep -rnE "nowarn\|-dialyzer\(" src/`; `git diff release/0.6.x..task/0.6.0-p6m7 -- rebar.config src/` shows no gate-loosening. | serious | `CLAUDE.md` never-loosen rule | open | | The finish-line risk: *"it's the last milestone, just suppress this one warning."* No. |
| P6M7-13 | **Ledger walk + closing report.** All 13 rows have a single valid final state (`done` / `deferred` / `no-op`; `done (amended criterion)` is fine) with grep/test-verifiable evidence. Closing tally arithmetically matches 13. Per-row dispositions; no prose summary. | The ledger has Status + Evidence on every row; the tally line at the bottom adds to 13. | serious | LEDGER_DISCIPLINE | open | | The last walk of the 0.6.0 arc. |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
milestone. `correctness` = a guarantee P6-M7 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to 0.6.x / 0.7

_(Filled in at close — e.g. per-tool `inputSchema` validation on `tools/call`
(0.6.1 candidate); the graph-RAG extension that Duncan has queued as the first
0.6.x extension; any P6-M6 acceptance defects that landed as deferrals; any
howto sections that were trimmed for scope and should grow in 0.6.1 docs. Note
any module still in `cover_excl_mods` with its re-entry milestone.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 13. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
0.6.0 tag: `<SHA>`. GitHub release: `<URL>`.
