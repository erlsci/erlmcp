# CC Prompt — erlmcp 0.6.0, M5b ledger close

> Imperative brief for **CC**. No code — this fills and closes the M5b ledger. The
> M5b work merged at `db03e58`; CDC has verified the substance (docs rewritten +
> accurate, README at 0.6.0, CodeQL + dependabot present, anti-drift clean). The only
> remaining step is the ledger bookkeeping. On the M5 branch.

## Why

`docs/0.6.0/milestones/M5b-docs-release-ledger.md` still has all 10 rows `open` and the
Closure block is `(Open.)`. The code/docs are committed (`db03e58`); the closing pass
was never done. Also, M5b-8 needs an **amendment** recorded (owner decision), not a
silent close.

## Tasks

1. **Fill `Status` + `Evidence` for M5b-1…M5b-10** (commit `db03e58`) with the actual
   evidence — the file rewritten + the cross-check that proves it. For the anti-drift
   rows, cite the clean grep (no deleted-module references outside the migration guide,
   which legitimately names the old 0.5 API in its left column).

2. **M5b-8 — record the amendment.** The criterion as written asks for a
   `CHANGELOG.md`. **Owner decision (2026-05-23, confirmed): no hand-maintained
   CHANGELOG** — release discipline is SemVer + published GitHub release notes + git
   history (now also a locked decision in `CLAUDE.md`). Reword the M5b-8 row to
   *"SemVer policy stated + release notes via Git tags/GitHub (no hand-maintained
   CHANGELOG, per owner decision)"* and mark it **`done`** with that rationale, citing
   the README's "Release notes are maintained in Git tags" line. This is a raised
   amendment, not a silent pass — note it in the row and the closing walk.

3. **Write the per-row closing walk**, fill `What Worked` and `Carry-forward`, and the
   **Closure block** (`Closed at db03e58 on 2026-05-23`; Total rows: 10; Done: 10;
   Deferred: 0; No-op: 0). Leave the **CDC verification line pending** — do not
   self-certify.

## Verify (what CDC will check)

- All 10 rows carry `Status` + real `Evidence`; M5b-8 reworded to the tags/GitHub
  amendment and marked `done` with rationale.
- Closing walk + `What Worked` + `Carry-forward` + Closure filled; CDC line pending.
- (No code changes — `git diff --stat` touches only the M5b ledger.)

## Out of scope

No code, no doc edits (those are committed and CDC-verified). No other ledgers.

## Done when

The M5b ledger is fully filled with M5b-8 recorded as the CHANGELOG→tags amendment, the
Closure block complete (CDC line pending), and it's submitted for CDC sign-off — the
last milestone ledger needed to fully close 0.6.0.
