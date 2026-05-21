# CC Prompt — M0 Amendment: scope the coverage gate (ledger row M0-12)

> Imperative brief for **CC**. Self-contained; load the linked rows before coding.
> **CDC** will re-run CI and check the included/excluded module split before M0-12
> closes.

## Why this exists

CI on `task/0.6.0-m0` is green on compile, xref, and eunit (83 tests, 0 failures)
but **fails the coverage gate: 38% < 90%**. Cause: M0-6 stood up ~16 *empty*
skeleton modules (0%), and several legacy modules are low because they are slated
for replacement/deletion. A flat 90% aggregate can't be met — and pouring tests
into code we're about to delete would be wasted effort.

The owner chose **"scope the gate to implemented modules."** This task implements
that. It is ledger row **M0-12** in
`docs/0.6.0/milestones/M0-decide-scaffold-clear-ledger.md` — read it first.

## The policy (apply exactly)

The gate enforces **≥90% over included modules only**. A module is **excluded**
(via `cover_excl_mods`) iff it is **either**:

- **(a) a not-yet-implemented skeleton** — no real logic landed yet (the M0-6
  modules and any other empty stub), **or**
- **(b) legacy slated for replacement/deletion** that has not yet been re-seated
  on the new core.

A module is **included** (must contribute to ≥90%) iff it has a real
implementation **and** is staying in 0.6.0.

Classify each module using **`docs/0.6.0/planning/phase1b-erlmcp-inventory.md`**
(what exists) and **`phase3-gap-analysis.md`** (what's kept vs replaced). When in
doubt whether a module is "kept" or "to-be-replaced," **raise it** rather than
guessing — the classification is a judgment call CDC should confirm.

**Expected for M0:** M0 implemented no new logic, so the included set will be
small — possibly only fully-covered behaviour modules. **That is correct and
honest; do not pad it.** The gate gains teeth as M1+ implements real modules. Do
**not** write tests for skeletons or for legacy modules headed for deletion just
to lift the number.

## Tasks

1. Add `cover_excl_mods` (in `rebar.config`, in the profile the CI `cover` step
   uses) listing every excluded module, classified per the policy above.
2. Confirm `rebar3 as test cover -v --min_coverage=90` **passes** locally over the
   included set.
3. Push `task/0.6.0-m0`; confirm CI is green (this also closes M0-11).

## Report back (for CDC review)

- The **included** module list (what the gate now measures) with each one's
  coverage %.
- The **excluded** list, each tagged `skeleton` or `to-replace` with a one-line
  reason and (for `to-replace`) the milestone that re-seats or deletes it.
- Confirm the gate is not hollow: if the included set is near-empty, **say so
  explicitly** — don't hide it.

## Working protocol (unchanged from M0)

- Branch `task/0.6.0-m0` (a `task/**` branch — CI fires on it; a bare
  `0.6.0-m0` does not).
- Commit the change; update M0-12's `Status`/`Evidence` (commit SHA + the passing
  `cover` output) in the same commit; mark M0-11 done with the green CI evidence.
- Raise amendments; never silently work around. 5-iteration cap.

## Out of scope

Do **not** implement skeleton modules or add feature logic to lift coverage. This
task only configures the gate's *scope*. Implementation of the excluded modules
happens in their own milestones, at which point they leave `cover_excl_mods`.
