# CC Prompt — P6-M2 iteration 3 (finish the EOF→node-halt chain)

> Imperative brief for **CC**. Short, focused finish for P6-M2. Iteration 3 of 5.
> Everything else is in: 17 of 18 rows closed, CI green expected on the push.
> The one remaining gap is the **last hop** of P6M2-9's chain — your own test
> comment names it correctly; the launcher just isn't there yet. Three small
> edits and the milestone closes honestly.

## What's left, and what the gap is

P6M2-9's criterion: *"stdin EOF triggers clean shutdown of the subtree — the OS
process exits; no hang."* You've delivered the first three hops:

```
EOF → reader exits normal → transport stops (good) → subtree terminates (good)
                                                  → app stops (good)
                                                  → ??? node should halt
```

But `examples/*/run.sh` still uses `application:ensure_all_started(<app>)` — the
**1-arg** form, which starts the app `temporary`. When a `temporary` app stops,
the **node does not auto-halt** — it lingers. Your own test comment in
`erlmcp_stdio_lifecycle_SUITE` names the intended chain correctly:

```
%% subtree (one_for_all, intensity 0) terminates → permanent app dies
%% → node halts. Test: transport process dies after reader EOF.
```

The intent is right; the launcher is one character short of delivering it. Fix
the launcher to actually run the app as `permanent`, then assert the *node*
exits end-to-end (not just the transport process).

## MUSTs

1. **MUST flip all three launchers to `/2 permanent`.** In
   `examples/simple/run.sh`, `examples/calculator/run.sh`,
   `examples/weather/run.sh`, change:
   ```
   -eval 'application:ensure_all_started(<app>)'
   ```
   to:
   ```
   -eval 'application:ensure_all_started(<app>, permanent)'
   ```
   No other changes to the launcher.

2. **MUST add a subprocess test that asserts the OS process actually exits on
   stdin EOF.** The existing `eof_shuts_down_transport` CT covers the transport
   hop — that stays. Add an *end-to-end* assertion via one of:
   - Extending `test/scripts/test_stdio_roundtrip.sh`: launch `examples/simple/run.sh`
     as a subprocess, send `initialize` + `notifications/initialized`, then close
     stdin, then `wait` for the process with a timeout (a couple seconds) — exit
     status must arrive, **not a timeout**. A timeout means the node lingered;
     that's the failure mode this test exists to catch.
   - Or a CT case (in `erlmcp_stdio_launch_SUITE` or a new
     `erlmcp_stdio_eof_SUITE`) that does the same via `open_port` and asserts a
     port-exit message within the timeout.
   Either is acceptable; pick the simpler one for your toolchain. The script
   route is closer to the regression we're guarding.

3. **MUST update P6M2-16's amended criterion text** to mention `/2` +
   `permanent`, so the launcher row and the EOF row tell the same story. The
   current Verify says `application:ensure_all_started/1` — change to
   `application:ensure_all_started/2` (with `permanent`). Update the grep
   verifies accordingly (e.g., `grep -q "ensure_all_started.*permanent"
   examples/simple/run.sh`).

4. **MUST close the P6M2-9 ledger row honestly.** Status `done`, Evidence cites
   both the transport-hop CT *and* the new end-to-end OS-process-exit test. No
   "intended" handwaves — the comment in `eof_shuts_down_transport` was already
   describing the right chain; the evidence has to match it.

5. **MUST keep everything else green.** No regressions: `make check` green;
   `make dialyzer` clean on 27 and 28; CI green on the pushed branch.

## Verify

- `grep "ensure_all_started" examples/{simple,calculator,weather}/run.sh` →
  each shows `ensure_all_started(<app>, permanent)`.
- The new subprocess/CT test passes locally and in CI.
- `eof_shuts_down_transport` (the transport hop) still passes.
- All 18 ledger rows have final Status + Evidence; per-row walk.
- `make check` exits 0; CI green on `task/0.6.0-p6m2`.

## Out of scope

- Anything beyond the three edits above. No new architecture, no new tests
  outside the EOF chain. M2 is otherwise closed.

## Done when

The launcher boots the app `permanent`; the end-to-end test asserts the OS
process exits on stdin EOF (within the timeout); P6M2-9 closes against a Verify
that exercises the *whole* chain its comment describes; P6M2-16's amendment text
mentions `/2 permanent`; CI green. Then M2 is genuinely closed and we open M3.
