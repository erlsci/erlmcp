# CC Prompt — erlmcp 0.6.0, M4 fix-up + M3b retroactive close

> Imperative brief for **CC**. Closes the CDC findings on M4 and the M3b ledger that
> merged without being closed. On `task/0.6.0-m4`. **CDC re-runs the Verify commands
> and reads your diffs — not your summary — before either milestone closes.**

## Context: what CDC found

M4's transport work is strong — tag unified across all transports, `streamable_http`
implemented, the registry + supervision coverage landed (`cover_excl_mods` now down
to only the M6 task modules). Three things remain:

- **M4-3 / M4-4 marked `done` below their ≥90% criterion** (`stdio` at 67%, `tcp` at
  88%), with no amendment raised. The aggregate sits at exactly 90%, masking the weak
  modules. This is the third recurrence of the M3a-13 pattern; the M4 prompt warned
  against it explicitly.
- **The M3b ledger was never closed.** M3b's code merged, but on disk
  `M3b-server-to-client-features-ledger.md` still has all 12 rows `open`, placeholder
  Closure, and no evidence — a milestone advanced without closing its verification
  contract.
- **M4's own ledger** still needs its closing pass.

## Standing coverage policy (read this first — it's the root cause)

**Newly-included modules must individually reach ≥90%.** The CI gate is *aggregate*,
but a per-module ledger row that says "holds ≥90%" means *that module*, not the
average. A high-coverage module may not be used to carry a low one over the line. If
a module genuinely cannot reach 90%, **raise an amendment** with a line-level gap
analysis (which specific lines are unreachable in test and why) — do **not** mark the
row `done`, and do **not** lean on the aggregate. "Aggregate 90%" is not evidence for
a per-module row.

## Tasks

### Phase A — M4 coverage (bring stdio + tcp to ≥90%)

1. **[M4-3] `erlmcp_transport_stdio` → ≥90%.** It is testable: `simulate_input/2` is
   exported, and `handle_info({line, _})`, the `{send, _}` path, `terminate/2`,
   `validate_config/1`, and the error branches are all reachable in EUnit/CT without a
   real stdin. The only plausibly-unreachable code is the `read_loop` `io:get_line`
   blocking call in the spawned reader. Write the missing tests to clear ≥90%. If the
   reader loop's blocking line(s) genuinely cannot be covered, exclude *only* via a
   raised amendment that names those exact lines — not the whole module.

2. **[M4-4] `erlmcp_transport_tcp` → ≥90%.** At 88% it's close; add tests for the
   uncovered branches (connect failure / reconnect, disconnect, buffer handling,
   `validate_config/1` rejects) to clear the bar.

3. Re-confirm the aggregate gate still passes and report **each** of `stdio`, `tcp`,
   `streamable_http`, `registry`, and the supervisors as an individual percentage in
   the evidence — not just the aggregate.

### Phase B — close the M4 ledger

4. Fill `Status` + `Evidence` for all 13 M4 rows in
   `docs/0.6.0/milestones/M4-transports-ledger.md` — commit SHA(s) + the actual Verify
   output / passing test name (what was *run*). For M4-3/M4-4, the evidence must show
   the **per-module** ≥90% number, not the aggregate.
5. Write the per-row closing walk (one line per row; no prose summary; name
   uncertainty), and fill `What Worked` and `Carry-forward to M5+`. In carry-forward,
   record: the behaviour-conformance suite feeding M5's scorecard; and whether
   M3b-10's cross-node test should migrate onto a real M4 transport.
6. Fill the `Closure` block; leave the **CDC verification line pending** (do not
   self-certify it).

### Phase C — retroactively close the M3b ledger

7. In `docs/0.6.0/milestones/M3b-server-to-client-features-ledger.md`, fill `Status` +
   `Evidence` for all 12 rows (commit `1d8dc3b`, plus `2757199` for the M3b-10
   cross-node epmd-skip fix) with the actual passing test names.
8. **Confirm the coverage the M3b ledger implicitly claims.** `erlmcp_client_session`
   absorbed the inbound-dispatch/callback/capability code in M3b (≈421 → 617 LOC).
   Report its **current** per-module coverage; it must be ≥90%. If it isn't, that's a
   real gap to close here too (Phase A policy applies). Note in M3b-9's evidence that
   the three behaviour modules are callback-only (no executable lines), so their
   "100%" is vacuous — the substantive coverage is `erlmcp_client_session`'s.
9. Write the M3b per-row closing walk, `What Worked`, and `Carry-forward to M4+`. In
   carry-forward, record the **`request_peer/3` peer-death robustness note**: a worker
   blocks up to the 30s timeout if the client peer dies mid-request, and the
   `out_pending` entry lingers until then; a proactive client-death → flush-out_pending
   path would fail faster (candidate hardening, not required now).
10. Fill the M3b `Closure` block; leave the **CDC verification line pending**.

### Commits

11. Commit the coverage work (Phase A) separately from the two ledger closes (Phase
    B/C). Three commits is fine.

## Acceptance / Verify

- `stdio` and `tcp` each report ≥90% individually; aggregate gate still passes;
  per-module percentages are in the evidence.
- `cover_excl_mods` still lists only `erlmcp_task` + `erlmcp_task_sup`.
- M4 ledger: 13 rows with `Status` + real (per-module where claimed) `Evidence`,
  closing walk, `What Worked`, `Carry-forward`, Closure (CDC line pending).
- M3b ledger: 12 rows filled, `erlmcp_client_session` current coverage ≥90% reported,
  closing walk + sections + Closure (CDC line pending).
- `rebar3 compile` (zero warnings), `xref`, `eunit`, CT, `proper`, `dialyzer` green;
  CI green on `task/0.6.0-m4`.

## Out of scope

No new features. No transport re-architecture. No `erlmcp_server_session` god-module
refactor (still a carry-forward). Do not touch already-verified rows beyond filling
their evidence.

## Done when

`stdio` and `tcp` are honestly ≥90% (or any sub-90% line is covered by a raised
amendment with line-level analysis); both the M4 and M3b ledgers are fully filled and
closed with CDC lines pending; gates and CI green; submitted for CDC sign-off.
