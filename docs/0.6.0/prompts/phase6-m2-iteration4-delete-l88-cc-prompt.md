# CC Directive — P6-M2 iteration 4 (delete the dead `{ok,Pid,_}` clause)

> Tiny finish for P6-M2. CI is green (P6M2-13 ✓). Only this remains, and it
> resolves cleanly per CLAUDE.md without an amendment if the arithmetic works.

## The one thing

Your own line analysis on `erlmcp_stdio_sup` named L88 as unreachable:

> *"`{ok,Pid,_}` variant never produced by our modules — unreachable."*

Per CLAUDE.md *Never loosen a check*:

> *"'this function is dead' is **deleted** (it's dead, and dead code often hides
> bugs — removing it has twice surfaced real defects in this repo)."*

So delete L88, don't excuse it.

## MUSTs

1. **MUST delete the `{ok, Pid, _}` clause** at `src/erlmcp_stdio_sup.erl` L88.
   It's `supervisor:start_child/2`'s 3-tuple success variant, which is only
   returned when a child's `init/1` returns `{ok, State, ExtraInfo}` — none of
   our children do, and none will. It's dead, delete it.

2. **MUST re-run coverage and update P6M2-11.** Two outcomes possible:
   - **`erlmcp_stdio_sup` clears ≥90% after the deletion** (likely — removing
     1 of 4 uncovered lines from a small module probably crosses the line):
     remove the amendment from P6M2-11, mark it a clean `done` against the
     original criterion. Update Evidence to reflect the new per-module figure.
   - **Still 89% / below 90%**: keep the row's amendment, but **with three
     named lines, not four** (L23 + L71/73; L88 gone). The amendment is
     legitimate for those three (defensive supervisor failure paths — genuine
     ceiling per the rule).

3. **MUST keep all other gates green.** `make check` exits 0; `make dialyzer`
   clean on 27/28; no regressions on the 18 ledger rows.

## Verify

- `! grep -nE "\\{ok, Pid, _\\}" src/erlmcp_stdio_sup.erl` — the dead clause is gone.
- `rebar3 as test cover -v --min_coverage=90` exits 0.
- `erlmcp_stdio_sup` per-module figure recorded in P6M2-11 Evidence (with
  amendment removed if ≥90%, or trimmed to 3 lines if still <90%).

## Out of scope

The other moderately-low modules (`erlmcp_app` 60%, `erlmcp_task_sup` 75%,
`erlmcp_transport_sup` 84%) — not P6-M2's per-module-floor scope per P6M2-11's
explicit naming. Forward note for the milestones that own them; don't address here.

## Done when

L88 is deleted; P6M2-11 reflects reality (clean `done` if coverage clears 90%,
trimmed amendment if not); `make check` green; CI green on the next push. Then
**M2 closes for real**: 18/18, no softpedalling.
