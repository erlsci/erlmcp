# CC Prompt — erlmcp 0.6.0, M2b iteration 2 + ledger close

> Imperative brief for **CC**. Closes the CDC findings on M2b, then fills and closes
> the ledger — all pre-M3 cleanup, on `task/0.6.0-m2b`. **CDC re-runs the Verify
> commands and reads your diffs — not your summary — before M2b closes.**

## Context: what CDC found at `3dee476`

The implementation is strong and the reuse claims hold (one `paginate/2`, one
`derive_capabilities/1`, one `maybe_notify/2` — no forks; the conformance harness
is real). Two things block a clean close, plus housekeeping:

- **M2b-10 — `completions` capability is not advertised.** `derive_capabilities/1`
  emits `tools`/`resources`/`prompts`/`logging` but never `completions`, even though
  `completion/complete` (M2b-8) is fully implemented. The feature is real but
  undiscoverable via the capability map.
- **M2b-12 has a matching blind spot.** `scenario_capabilities_derived` asserts the
  other four families but **not** `completions` (it checks `tools`/`resources`/
  `prompts`/`logging` only), so the harness "passing" never caught the gap.
- Housekeeping: stale `cover_excl_mods` tags, an unstated scope narrowing on M2b-2,
  and the ledger's `Status`/`Evidence` columns are still `open`.

## Tasks

### Phase A — fix the `completions` gap (real correctness fix)

1. **[M2b-10]** In `derive_capabilities/1`, advertise the `completions` capability
   when completion is supported. Completion support mirrors logging here (the
   `completion/complete` handler always exists), so advertise `completions => #{}`;
   if you prefer to gate it on "any completer registered" that is also acceptable —
   but it **must** appear whenever the example servers register completers. Keep it
   the same single derived function; do not add a parallel capability builder.

2. **[M2b-12]** Extend `scenario_capabilities_derived` in `test/erlmcp_conformance.erl`
   to also assert `completions` is present in the derived capability map. Re-run the
   server scorecard; the score must still be ≥ 87.5% (it should rise, since this
   scenario now checks the thing the fix added). If adding the assertion *drops* the
   score, that means something else regressed — stop and report it.

3. **Logging note (minor).** `derive_capabilities/1` advertises `logging`
   unconditionally. That is defensible (logging is always supported), but it diverges
   from M2b-10's "only when registered/supported" wording. Either gate it consistently
   with the others, or leave it unconditional and **state the rationale in M2b-10's
   Evidence**. Your call; just make it explicit rather than silent.

### Phase B — housekeeping (no behavior change)

4. **Re-tag `cover_excl_mods`.** The comments tag `erlmcp_app`, `erlmcp_registry`,
   `erlmcp_server_sup`, `erlmcp_sup`, `erlmcp_transport_sup` as `% M2b: …`, but M2b
   never scoped a registry/supervision rewrite — those tags are inaccurate. Re-tag
   them to **`% M4`** (the supervision tree + registry coverage lands with transports,
   where they're exercised end to end; M5 is the 95% backstop). Do **not** remove the
   modules from the list — only correct the milestone tag. M2b-13 stays `done`
   (M2b added no standalone modules; its surface is inside the already-covered
   `erlmcp_server_session`, and the gate holds at 91%).

5. **M2b-2 scope (note only).** You implemented **level-1** URI-template matching;
   the ledger said "RFC 6570." Level-1 (`{var}`) is the common MCP case and is
   accepted — record in M2b-2's Evidence that the scope is level-1 explicitly (not
   full RFC 6570 levels 2–4), so the narrowing is on the record.

### Phase C — close the ledger

6. **Fill `Status` + `Evidence` for all 14 rows** of
   `docs/0.6.0/milestones/M2b-resources-prompts-logging-completion-ledger.md`.
   `Status` = `done` (or `deferred`/`no-op` with reason if you now judge otherwise).
   `Evidence` = commit SHA(s) (`3dee476` + this iteration's commit) **plus** the actual
   Verify output / passing test name — what was *run*, not a restatement of the
   criterion.

7. **Write the per-row closing walk** (one line per row, disposition + evidence; no
   prose summary; name uncertainty), and fill **`What Worked`** and
   **`Carry-forward to M3+`**. In carry-forward, record:
   - **God-module watch:** `erlmcp_server_session` is now ~1100 lines handling the
     entire protocol surface. Do **not** refactor it in this iteration (too risky
     right before M3) — flag it as a carry-forward candidate for extracting per-feature
     handler modules.
   - The registry/supervision coverage now tagged `% M4` (above).

8. **Fill the `Closure` block.** `Closed at commit <SHA> on <date>. … Total rows: 14.
   Done: <n>. Deferred: <n>. No-op: <n>.` Leave the **CDC verification line pending** —
   do not self-certify it.

9. **Commit** the fix (Phase A/B) and the ledger close (Phase C) — two commits is fine
   ("M2b iteration 2: advertise completions capability + conformance assertion" and
   "M2b: close ledger").

## Acceptance / Verify

- `grep -n 'completions' src/erlmcp_server_session.erl` shows `completions` added to
  the derived capability map.
- `scenario_capabilities_derived` asserts `completions`; `run_server_scorecard`
  score ≥ 87.5%.
- `cover_excl_mods` tags for the five infra modules read `% M4`; the modules remain
  listed; `rebar3 as test cover -v --min_coverage=90` still passes.
- All 14 M2b rows carry `Status` + real `Evidence`; closing walk, `What Worked`,
  `Carry-forward`, and `Closure` (CDC line pending) are filled.
- `rebar3 compile` (zero warnings), `xref`, `eunit`, CT, `proper`, `dialyzer` green;
  CI green on `task/0.6.0-m2b`.

## Out of scope

No refactor of `erlmcp_server_session` (carry-forward only). No registry/supervision
rewrite (that's M4). No new features. No touching the already-CDC-verified M2a rows.

## Done when

The `completions` capability is advertised and asserted in conformance, the
`cover_excl_mods` tags are corrected, the M2b ledger is fully filled and closed (CDC
line pending), gates and CI are green, and the work is submitted for CDC sign-off.
