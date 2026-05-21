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
  by M5.
- **Error handling:** validate at the edge, crash in the interior; translate crashes
  to JSON-RPC errors at the session↔worker boundary (Phase 2 §5).
- **No shared records** across module boundaries or in exported specs; opaque types
  + accessor functions.
- **No `_new` forks; no macros for logic** (house style). One way to do a thing.

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
- [ ] Ledger rows updated with evidence; per-row closing report written.
- [ ] Self-reviewed against the Erlang skill (`priv/ai/erlang/SKILL.md`).
