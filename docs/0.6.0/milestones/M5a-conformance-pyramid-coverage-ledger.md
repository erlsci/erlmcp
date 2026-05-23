# Milestone M5a: Conformance scorecard, test pyramid, specs & coverage

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state. No milestone advances until the ledger is fully closed.

**Goal:** the quality artifact that earns "same quality as rmcp" — a dated, versioned,
published conformance scorecard; the full test pyramid; `-spec`/`-type` on all
exports; and the coverage ratchet to its 95% endpoint. M5a is the first half of the
former M5; **M5b** is the docs rewrite + release automation.

**Locked decisions (carried):** JSON via `erlmcp_codec`; `jesse` at the edge; OTP 25+;
validate at the edge, crash in the interior; no shared records; no `_new` forks; no
macros for logic. **Per-module coverage policy (standing):** a newly-included module
must individually reach the floor; the aggregate may not carry a weak module; a true
ceiling needs a raised amendment with line-level analysis.

**Branch:** `task/0.6.0-m5a`, cut from `release/0.6.x` (after M4 lands); PR into
`release/0.6.x`. Depends on M1–M4 (the full implemented surface). All Verify commands
run from the repo root. All rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| M5a-1 | `erlmcp_conformance` emits a **dated, versioned** scorecard (server + client + transport, L0–L4) as a committed artifact mirroring rmcp's `conformance/results/*` layout. | Running the scorecard writes a dated/versioned results file; the file is committed; it lists each scenario's level + pass/fail + an overall score. | serious | dev plan M5a; Phase 2 §9 | open | | Harness already exists (M2b/M3b/M4); M5a formalizes the published artifact. |
| M5a-2 | Protocol-native discoverability surfaces (`instructions`, tool `_meta`, `annotations`, resources) are scored as capabilities in the scorecard; the **directory tool is excluded**. | Scorecard includes discoverability scenarios; `grep` of the scored set shows no `directory` tool entry (DISC-6). | serious | dev plan M5a; `m2-discoverability-design.md` §7 (DISC-6) | open | | The one erlmcp extension stays out of the spec scorecard. |
| M5a-3 | The published scores meet or exceed rmcp's reference across L0–L4 (server, client, transport). | The scorecard's server/client/transport scores ≥ the documented rmcp reference; the reference figures are cited in the artifact. | serious | dev plan M5a DoD | open | | If a score falls short, raise it with a gap analysis — do not redefine the bar. |
| M5a-4 | Full test pyramid is present and CI-enforced: EUnit (units, 1–2 asserts), Common Test (lifecycle/transport/e2e), PropEr (envelope + state-machine fuzzing). | CI runs all three layers; `rebar3 proper` passes the envelope + session-lifecycle properties; CT covers lifecycle/transport/e2e; EUnit unit suites present. | serious | dev plan M5a; Phase 2 §9 | open | | Consolidates the layers built across M1–M4 into an enforced pyramid. |
| M5a-5 | Every exported function across the implemented modules has a `-spec`; every exported type a `-type`/`-opaque`. | A check (script or `grep`) reports **zero** exported functions without a `-spec` in `src/`; Dialyzer succ-typing clean. | serious | dev plan M5a; Phase 2 §2; closes B (specs) | open | | "On all exports" — the spec-completeness gate. |
| M5a-6 | Coverage debt resolved and the gate ratcheted toward 95%: every implemented module ≥90% (M4's `stdio`/`server_sup`/`sup` amendments resolved to the floor or formally accepted with line-level rationale); the aggregate gate is raised to the highest honest threshold toward 95%; only `erlmcp_task`/`erlmcp_task_sup` (M6) remain excluded. | `cover` passes at the raised `--min_coverage`; `cover_excl_mods` lists only the two M6 modules; any sub-90 module carries a CDC-acceptable named-line amendment. | serious | dev plan M5a (90%→95% endpoint); closes B (coverage); standing per-module policy | open | | If 95% aggregate isn't honestly reachable given named-unreachable lines, raise an amendment with the gap — do not pad. |
| M5a-7 | Dialyzer clean and xref clean, enforced in CI as standing gates. | `rebar3 dialyzer` exit 0; `rebar3 xref` clean; both in the CI pipeline. | serious | dev plan M5a | open | | |
| M5a-8 | CI runs the full pipeline green on `task/0.6.0-m5a`. | CI (compile+xref+eunit+CT+proper+dialyzer+cover@raised-gate) green on the branch. | serious | dev plan M5a DoD | open | | |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
credibility artifact. `correctness` = a guarantee the feature claims. `polish` =
hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to M5b/M6

_(Filled in at close — e.g. the scorecard artifact M5b's docs link to; any module
whose coverage ceiling is a named amendment; task-module coverage deferred to M6.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 8. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
