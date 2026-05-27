# CLAUDE.md — erlmcp

Standing instructions for Claude (including Claude Code / "CC") working in this
repository. Auto-loaded each session. Keep it short; keep it followed.

## What erlmcp is

erlmcp is an Erlang/OTP implementation of the Model Context Protocol (MCP). The
active effort is the **0.6.0 re-core** — a clean rebuild around a `gen_statem`
session + per-request-process spine, matching the Rust SDK (rmcp) on quality and
beating it where the BEAM is stronger (cancellation, fault isolation, supervised
tasks). Break freely; the 0.5.0 API is not preserved.

All 0.6.0 planning, contracts, and work briefs live under `docs/0.6.0/`:

- `docs/0.6.0/planning/` — strategy & design (phase0–phase5, the dev plan, the
  discoverability design).
- `docs/0.6.0/milestones/` — per-milestone **ledgers** (the verification contracts).
- `docs/0.6.0/prompts/` — per-milestone **CC briefs** (imperative task lists).

## House style — load this first

Before writing or reviewing Erlang, read **`priv/ai/erlang/SKILL.md`** and follow
its own loading instructions (it indexes `priv/ai/erlang/guides/`). This is the
authoritative erlmcp Erlang skill and the operative code-quality reference. It is
built on the Inaka/OTP rubric captured in `docs/0.6.0/planning/phase0-erlang-rubric.md`.

## Locked decisions (0.6.0)

- **JSON:** `jsx`, accessed **only** through `erlmcp_codec`. No `jsx:` calls elsewhere.
- **Schema validation:** `jesse`, wired at the session boundary (validate at the edge).
- **Minimum OTP:** 25+. No features newer than OTP 25 (no `-doc`/EEP-48 attributes;
  use edoc/ex_doc).
- **Coverage gate:** 90%, **scoped** to implemented modules via `cover_excl_mods`;
  the exclusion list shrinks each milestone until it covers everything at 90%→95%
  by M5. **Per-module, not just aggregate:** a newly-included module must itself
  reach the floor — a high-coverage module may not be used to carry a weak one over
  an aggregate line. **"Unreachable" requires line-level proof** that the code
  cannot be driven from any test; *"we didn't write the test yet"* and *"this
  function is dead"* are **not** unreachability — the former is **covered** (write
  the test), the latter is **deleted** (it's dead, and dead code often hides bugs —
  removing it has twice surfaced real defects in this repo). A genuine ceiling
  (e.g. an `io:get_line` blocking loop) is closed by a **raised amendment that names
  the exact uncovered lines**, not a blanket sub-90 `done`.
- **Error handling:** validate at the edge, crash in the interior; translate crashes
  to JSON-RPC errors at the session↔worker boundary (Phase 2 §5).
- **No shared records** across module boundaries or in exported specs; opaque types
  + accessor functions.
- **No `_new` forks; no macros for logic** (house style). One way to do a thing.
- **Release discipline:** SemVer + published release notes (GitHub releases) + the
  git history. **No hand-maintained `CHANGELOG`** — it's a holdover from before
  queryable version control; the git log and published release notes cover it. Don't
  write a CHANGELOG requirement into ledgers or docs checklists.

## Never loosen a check to make it pass — hard rule, no exceptions without sanction

A failing check — compiler warning, Dialyzer/type warning, linter, xref, test, or
coverage gate — is **information about a real defect**. Silencing the check destroys
the information and ships the defect. **Making the check's *output* go away instead
of fixing the code is forbidden.** This is the most important rule in this file. It
has been violated repeatedly across many languages; here it is treated as a serious
process failure, not a shortcut.

**Forbidden — never do any of these to reach green (in *any* language/tool):**

- **Inline suppressions:** `-dialyzer(...)` / `nowarn_*`, `% eslint-disable`,
  `#[allow(...)]`, `# type: ignore` / `# noqa`, `@ts-ignore` / `@ts-nocheck`,
  `//nolint`, `@SuppressWarnings`, `# rubocop:disable`, and every equivalent.
- **Loosening config:** removing or disabling warnings/lint rules, turning off
  `warnings_as_errors`, lowering a coverage threshold, adding modules to
  `cover_excl_mods` / ignore-lists / exclude-globs, relaxing a compiler or
  type-checker flag.
- **Type laundering:** widening a spec/type to `term()` / `any()` / `dynamic` /
  `Object` to silence a type warning instead of stating the true type.
- **Spec-to-bug fitting:** editing a `-spec`/type to match what buggy code *does*
  rather than fixing the code to do what it *should*.
- **Test evasion:** deleting, skipping, `@ignore` / `.skip` / `xit` / commenting
  out, or weakening assertions on a failing test; widening a property's bounds to
  pass.

**The principle: make the code satisfy the check, not the check satisfy the code.**
A check that fires found something before a user did.

**The only sanctioned path when a check looks *wrong*:** stop and **escalate** to
CDC/Duncan with the exact `file:line` and why you believe it's a false positive or
genuinely unreachable. Do not decide unilaterally, and do not loosen as a first
move. A real false positive is then closed by a **narrow, single-site, commented,
approved** exception naming the reason and who sanctioned it — never a broad or
silent loosening. If a proper fix is out of scope, that is a **disclosed deferral
with a re-entry condition**, not a suppression. (Cf. the coverage rule above: a
genuine ceiling is a *raised amendment naming exact lines*, not a blanket pass.)

Strict checks were turned **on** here deliberately (e.g. the un-suppressed Dialyzer
warning set, `warnings_as_errors`). Turning them back down to pass is exactly the
regression this rule exists to prevent.

## How we work (process rigour)

Two roles. **CC** implements and self-assesses. **CDC** (a separate context /
reviewer) independently verifies — re-running Verify commands and reading diffs,
not summaries. The implementer does not mark its own work verified.

Every milestone has a **ledger**: the contract of what "done" means, one row per
acceptance criterion with a grep/test-verifiable Verify command. Read
**`priv/ai/LEDGER_DISCIPLINE.md`** and the relevant
`docs/0.6.0/milestones/*-ledger.md` **before writing code**. Then:

- Work against the ledger. Update each row's `Status`/`Evidence` (commit SHA +
  Verify output) in the commit that closes it.
- If a criterion is wrong, impossible, or needs a later milestone, **raise an
  amendment** — never silently work around it.
- Closing report = a **per-row walk**: a final disposition for every row
  (`done`+evidence / `deferred`+reason+re-entry / `no-op`+rationale). No prose
  summaries; never "deviations: none". Name uncertainty.
- **Iteration cap: 5** per milestone.

Write to the floor, not the ceiling: state what the work actually achieves, name
what is not done, and distinguish "verified by running X" from "I believe X".

## Subagent Delegation Policy

(full text: `priv/ai/SUBAGENT-DELEGATION-POLICY.md`)

- **Do not delegate thinking work to subagents** — code edits, design/architecture
  decisions, tradeoff reasoning, judging whether a finding is real, planning,
  evaluating correctness.
- **Subagents are for lookup only** — finding files/symbols, grepping, reading a
  file, fetching docs: retrieval that needs no judgment about the result.
- Serial on thinking (main context); parallel on lookup. Quality over wall-clock
  on the thinking path.

## Branches & CI

- Integration branch for the re-core: **`release/0.6.x`** (`main` stays on 0.5.x).
- Milestone branches: **`task/0.6.0-mN`**, cut from `release/0.6.x`, PR'd back into it.
- CI (`.github/workflows/ci.yml`) fires on `main`, `release/**`, `task/**`,
  `feature/**`, `epic/**`, and tags — **not** a bare `0.6.0-mN`, so use the `task/`
  prefix. CI is the independent reproducer for compile/xref/eunit/CT/PropEr/
  Dialyzer/coverage (the matrix runs OTP 25–28).

## Collaboration posture

Peer frame: equal contributors, mutual intellectual humility, honest engagement
over agreeable hedging. Being corrected is a contribution, not a defeat. See
`priv/ai/AI-CONSTITUTION-SUPPLEMENT.md` and `priv/ai/AI-ENGINEERING-METHODOLOGY.md`.

## Before submitting

- [ ] `rebar3 compile` clean, **zero warnings** (`warnings_as_errors` is on).
- [ ] `rebar3 xref` clean.
- [ ] `rebar3 eunit` + Common Test green; PropEr properties pass where defined.
- [ ] `rebar3 dialyzer` clean.
- [ ] Coverage gate passes (scoped per `cover_excl_mods` in `rebar.config`).
- [ ] **No check was weakened to reach green** — no suppressions, no loosened
      config/flags, no type laundering, no spec-to-bug fitting, no skipped/deleted
      tests (see *Never loosen a check to make it pass*).
- [ ] Ledger rows updated with evidence; per-row closing report written.
- [ ] Self-reviewed against the Erlang skill (`priv/ai/erlang/SKILL.md`).
