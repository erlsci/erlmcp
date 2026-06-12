# CC Prompt — P6-M6 iteration 2 (run the commands; split the conflated row; close)

> Imperative brief for **CC**. Iteration 2 of 5. The substantive content work in
> iter-1 is real and good — identity blocks, `protocol_features`, the M3
> machinery bet confirmed, READMEs rewritten, original-bug shapes verifiably
> gone, spine frozen (zero diff on `src/erlmcp_*.erl`). Seven rows closed
> cleanly. This iteration corrects **three rows** that need a different shape
> of close: one disposition that conflates two things, two deferrals that
> haven't been empirically tested. Every item is a **MUST**. Read all of it
> before editing.

## What worked in iter-1 — name it, then move on

- The spine is observably frozen. `git show 3c69655 -- src/erlmcp_*.erl` is
  empty. The unification claim survives M6.
- The identity blocks are substantive (real `purpose` strings, real `source`
  URLs, not placeholders).
- The three `protocol_features` declarations are honest — each matches the
  handler's actual behaviour (calculator `slow_compute` does call
  `report_progress`; calculator `explain` does call `request_peer`; weather
  template does carry a `completions` map).
- The `instructions_readable` CTs confirm the M3 machinery bet without author
  overrides — *machinery + content = no override needed*. That's a real
  payoff.
- READMEs carry the two model-facing sections the brief asked for.
- The grep-based original-bug closure (`type => emoji` / `taskSupport =>
  allowed`) is observably clean.

Keep all of that; don't relitigate it.

## What needs correcting — two distinct kinds of issue

### Kind A: P6M6-7 disposition conflates two things

The criterion requires **verdicts** (pass/partial/fail) per example. The
procedure is documented; the verdicts are *placeholder ("pending — Awaiting
human test")*. Calling that *"done (amended criterion)"* conflates *procedure
documented* with *verdict landed*. They're separable, and LEDGER_DISCIPLINE
wants them separated.

**Fix:** split the row.

- **P6M6-7a** — *Acceptance procedure documented*. Verify: the doc exists at
  `docs/0.6.0/acceptance/phase6-claude-desktop-acceptance.md`, has per-example
  procedure + expected state + verdict cell + follow-up cell, and is
  reproducible by a human with Claude Desktop. **Close `done`.**
- **P6M6-7b** — *Acceptance verdicts landed*. Verify: each example's verdict
  cell is one of `pass` / `partial` / `fail` (not `pending`); any `partial` /
  `fail` has a tracked follow-up. **Close `deferred` with explicit re-entry
  condition: verdicts MUST land before the 0.6.0 tag in P6-M7. Cite this as a
  P6-M7 prerequisite in M7's `RELEASE-CHECKLIST.md` row.**

The split is honest about the work-ownership boundary (CC writes the
procedure; Duncan executes it on Claude Desktop). It also keeps the 0.6.0 tag
gated on the verdicts actually landing.

Update the ledger to be a **13-row file** (was 12). Renumber nothing — the
existing IDs 1–6 / 8–12 stay; insert 7a and 7b in place of the old 7. Update
the tally line and the row-count phrasing in P6M6-12 ("12 rows" → "13 rows").

### Kind B: P6M6-9 and P6M6-10 deferred without empirical test

Both are reasoned deferrals based on what the wiring *seems* to require, not
on what running the actual command reports. The reasoning for P6M6-9 doesn't
match the file:

- `rebar.config` L35–39: the **test profile includes** `examples/simple/src`,
  `examples/calculator/src`, `examples/weather/src` via `extra_src_dirs`.
- `rebar.config` L47: `cover_enabled, true` in the test profile.
- `rebar.config` L137–140: `cover_excl_mods` excludes
  `erlmcp_transport_tcp` and `erlmcp_transport_http` *only* — **not** the
  example modules.
- The actual server module names are `simple_server`, `calculator_server`,
  `weather_server` (confirmed against source). There are no
  `example_*_handler` modules in `test/`.

So under the actual config, the example server modules **should** be in scope
for cover when `rebar3 as test cover` runs. CC's iter-1 description ("they
appear as `example_*_handler` modules, not the server modules themselves")
doesn't match the file. **Run the command and report what actually comes
back.**

**MUST 1 — run the cover command and report empirical state.**

`rebar3 as test cover -v --min_coverage=90`. For each of `simple_server`,
`calculator_server`, `weather_server`, report:

- Is the module present in the cover output? (it should be)
- What's the per-module figure?
- If ≥ 90%: close `done` with the figure as evidence.
- If < 90%: identify the uncovered lines. For each: either *write the test*
  (if the line is reachable) or *name the line + per-line reason* (if it's a
  genuine ceiling — defensive handler clause, blocking I/O loop, etc.). Close
  `done (amended criterion)` with the named-ceiling list, M2/M4-precedent
  format.
- If a module is **not** present in cover output despite being in
  `extra_src_dirs` of a cover-enabled profile: that's a real tooling finding
  — report the exact reason (a `rebar3` quirk, a build-order issue, an
  `extra_src_dirs` interaction). Then either fix the wiring (small
  `rebar.config` change is in scope for M6) or escalate with specifics.

**MUST 2 — run the dialyzer command and report empirical state.**

`make dialyzer` runs `rebar3 dialyzer` in the default profile, which does *not*
have `extra_src_dirs` for examples — so the example modules likely aren't in
scope for it. Try `rebar3 as test dialyzer`: does it analyze the example
modules? If yes, report findings (clean / a named warning list). If no, name
the precise reason and either:

- Add a small per-profile dialyzer config to the `simple` / `calculator` /
  `weather` profiles in `rebar.config` so each can be analyzed (small
  config-only change, in scope for M6), OR
- Escalate with specifics if it's a genuine tooling gap.

Either way: **the disposition lands against empirical data, not a guess about
the wiring.**

If, after running both commands, you find a real reason the gate can't be
honoured — e.g. `rebar3 cover` genuinely doesn't pick up `extra_src_dirs`
modules in some version, or per-profile dialyzer needs PLT machinery that's a
day's work — *then* the deferral is the right answer, and the evidence will
say *exactly* what was tried and what failed. That's the M2/M4 precedent for
honest deferrals: not "the wiring isn't there" but "I ran X, it returned Y,
here's why that means the criterion is unreachable from here."

## MUSTs (summary)

### 1. MUST run `rebar3 as test cover -v --min_coverage=90` and report empirical state per module

See Kind B above. Close P6M6-9 against what came back, not against what was
assumed.

### 2. MUST run dialyzer against the example modules and report empirical state

See Kind B above. Close P6M6-10 against what came back, not against what was
assumed.

### 3. MUST split P6M6-7 into procedure (done) and verdict (deferred)

See Kind A above. Ledger goes from 12 to 13 rows. Tally and P6M6-12's row
count phrasing update accordingly.

### 4. MUST keep every other gate green

- `make check` exits 0.
- `make compile-examples` exits 0.
- Spine stays frozen (`git show <iter2-commit> -- src/erlmcp_*.erl` empty).
- Examples stay essentially frozen — any iter-2 example-side change must be
  *minimal and named* (e.g. a one-line `-ifdef` for a test-only hook to make a
  defensive clause reachable). If you find yourself opening
  `examples/*/src/*.erl` for more than a trivial edit, **stop and escalate**.
- No new suppressions (`! grep -rnE "nowarn\|-dialyzer\(" src/ examples/`).

### 5. MUST push for CI

P6M6-11 retires when the branch is pushed. No code change for it; just the
push, once 1–4 are in.

## Iteration cap

This is iteration 2 of 5. The remaining items are bounded — run two commands,
split one ledger row, possibly write a few small tests if cover comes back
under 90% on a server module, possibly add per-profile dialyzer config (a few
lines in `rebar.config`). If running the cover or dialyzer command surfaces a
real tooling gap that genuinely can't be closed inside M6, **stop and escalate
with the exact command output** — and "escalate" means *stop and tell
CDC/Duncan*, not *defer and move on*. M5 taught us *escalate ≠ defer* and
*observable symptom ≠ satisfied criterion*; M6's lesson is *deferral requires
empirical evidence*, not a wiring story.

## Done when

`rebar3 as test cover -v --min_coverage=90` has been run and its output is the
evidence on P6M6-9 (either `done` with per-module figures, `done (amended
criterion)` with named-ceiling list, or `deferred` with the exact command +
output that proves the gate can't be reached); dialyzer has been run against
the example modules and its output is the evidence on P6M6-10; the ledger has
13 rows (P6M6-7 split into 7a/7b), the tally adds to 13, and P6M6-12 says "13
rows"; `make check` green; spine frozen; CI green on the pushed branch.
**Then M6 closes for real: 13 of 13, no conflated dispositions, no untested
deferrals.**
