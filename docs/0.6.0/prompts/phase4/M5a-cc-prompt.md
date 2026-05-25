# CC Prompt — erlmcp 0.6.0, Milestone M5a (Conformance scorecard, test pyramid, specs & coverage)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M5a closes.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M5a only**: the quality artifact
— a dated, versioned, published conformance scorecard; the full test pyramid;
`-spec`/`-type` on all exports; and the coverage ratchet to its 95% endpoint. **No
docs rewrite, no release automation** — that's M5b. The feature surface is done
(M1–M4); M5a is verification, specs, and coverage.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M5a-conformance-pyramid-coverage-ledger.md`** — the M5a
   ledger (rows M5a-1…M5a-8). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first**.
4. **`test/erlmcp_conformance.erl`** — the existing harness (`run_server_scorecard/0`,
   `run_client_scorecard/0`, `run_transport_scorecard/0`; L0–L4 scenarios). You
   formalize its output into a committed, dated, versioned artifact.
5. **`docs/0.6.0/planning/m2-discoverability-design.md`** §7 (DISC-6: directory tool
   excluded from the scorecard) and **`phase2-idiomatic-erlmcp.md`** §9 (testing).

## Locked decisions (non-negotiable)

- JSON via `erlmcp_codec`; `jesse` at the edge; OTP 25+; no macros for logic; no
  shared records; validate at the edge.
- **Per-module coverage policy (standing):** a newly-included module must
  individually reach the floor. The aggregate may **not** carry a weak module. A true
  ceiling needs a **raised amendment with line-level analysis** — not a `done` at
  sub-floor and not leaning on the aggregate. (This caused three prior recurrences;
  do not repeat it.)
- **Directory tool is excluded from the scorecard** (DISC-6). Discoverability's
  protocol-native surfaces (`instructions`, `_meta`, `annotations`, resources) are
  scored.

## Tasks (keyed to ledger rows; suggested order)

1. **[M5a-1]** Emit a dated, versioned scorecard artifact (server+client+transport,
   L0–L4) to a committed results path mirroring rmcp's `conformance/results/*`. Each
   scenario: level + pass/fail; an overall score.
2. **[M5a-2]** Ensure discoverability surfaces are scored; the directory tool is
   excluded (DISC-6).
3. **[M5a-3]** Confirm server/client/transport scores ≥ rmcp's documented reference;
   cite the reference figures in the artifact. If short, raise it — don't move the bar.
4. **[M5a-4]** Consolidate the test pyramid: EUnit units, CT lifecycle/transport/e2e,
   PropEr envelope + state-machine properties — all CI-enforced.
5. **[M5a-5]** Add `-spec` to every exported function and `-type`/`-opaque` to every
   exported type across `src/`. Provide/keep a check that reports **zero** unspecced
   exports.
6. **[M5a-6]** Resolve the coverage debt: bring every implemented module to ≥90%
   (resolve M4's `stdio`/`server_sup`/`sup` amendments to the floor, or formally
   accept them with **line-level** rationale), raise the aggregate gate toward 95%,
   and leave only `erlmcp_task`/`erlmcp_task_sup` excluded. If 95% aggregate isn't
   honestly reachable given named-unreachable lines, **raise an amendment** with the
   gap analysis.
7. **[M5a-7]** Dialyzer clean + xref clean, enforced in CI.
8. **[M5a-8]** Full CI pipeline green at the raised gate.

## Working protocol

- **Branch:** `task/0.6.0-m5a`, cut from `release/0.6.x` (after M4 lands); PR into
  `release/0.6.x`.
- Commit per ledger row (or coherent group); update `Status`/`Evidence` in the
  closing commit, reporting **per-module** coverage numbers where a row claims a floor.
- Raise amendments; never silently work around. **Do not mark any coverage row `done`
  below its floor without a raised, line-level amendment.**
- Closing report: a per-row walk over all 8 rows; no prose summary; name uncertainty.
- Iteration cap: 5. Subagents for lookup only.

## Out of scope for M5a (do NOT build)

The docs rewrite, README, migration guide, examples-on-core wiring, CHANGELOG/SemVer,
CodeQL/dependabot — **all M5b**. Tasks — **M6**. No new features.

## Done when

The dated/versioned scorecard is committed and ≥ rmcp's reference; the test pyramid
is CI-enforced; all exports carry specs; coverage debt is resolved (every module ≥90%
or a named-line amendment) with the gate ratcheted toward 95% and only M6 task modules
excluded; Dialyzer/xref/CI green; the closed ledger is submitted for CDC review.
