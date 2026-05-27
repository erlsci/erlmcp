# CC Prompt — Phase 6 / P6-M1 iteration 4 (test consolidation + close the gates)

> Imperative brief for **CC**. Continues iteration 3. CDC verified that the
> conformance/client work (iter-3 MUSTs 1–4) landed and that the remaining red is
> **not** a code regression. **Iteration budget: this is iteration 4 of 5** on the
> P6-M1 ledger — the last routine pass before the cap. Every item is a **MUST**.
> Read all of it first.

## State at the start of this pass (read carefully — the situation moved)

Iteration 3 already **fixed** the 12 failures + 3 cancelled by *migrating*
`erlmcp_session_tests` to the new core API — so `make check` now exits 0 and the
file (48 cases) passes. **The red is gone; this is not a debugging pass.** What
remains is (a) the coverage gate, (b) the ledger walk, (c) de-duplication, and
(d) CI. Two facts to hold:

- **`make check` does NOT enforce the 90% gate.** `make check` =
  `clean compile xref dialyzer test`, and `test` = `eunit, proper, cover` (plain
  `cover`, **not** `--min_coverage=90`). The 90% gate lives only in CI. So
  "make check exits 0" is **not** "all gates green" — the cover gate (P6M1-14) is
  still failing at ~82% aggregate with `cover_excl_mods=[]`.
- **`erlmcp_session_tests` (48 cases) now duplicates `erlmcp_server_session_SUITE`
  (50 cases)** for the same module. Coverage of `erlmcp_server_session` already
  meets ≥90% via the SUITE (iter-2), independent of this file. Operational ping is
  verified working (conformance `scenario_initialize`→`scenario_ping` on the shared
  session; SUITE pings after init) — do not re-debug it.

**Decision (Duncan): retire `erlmcp_session_tests`** — even though it now passes,
it is redundant with the SUITE; sunk migration effort does not justify shipping two
suites for one module ("one way to do a thing"). Audit → fold uniques → delete.

## MUSTs

1. **MUST audit `erlmcp_session_tests` (48 cases) against `erlmcp_server_session_SUITE`
   (50 cases).** Produce a fold-list: every `erlmcp_session_tests` case whose
   *behavioural intent* is **not** already covered by the SUITE (watch specifically
   for: the **batch** request/ping path, specific JSON-RPC **error codes**
   (-32600/-32601/-32602/-32603/-32002/-32003), notification paths, cancellation/
   worker-crash isolation, and any state-transition edge the SUITE misses).

2. **MUST fold the genuinely-unique cases into `erlmcp_server_session_SUITE`** on the
   new core API (per-test fresh session, drained mailbox, `responder`/`erlmcp_server`
   setup — no shared-process bleed). Folded tests must **assert on responses**, not
   just call-and-ignore (no vacuous tests).

3. **MUST delete `erlmcp_session_tests.erl`** once its unique coverage is folded.
   This clears the 12 failures + 3 cancelled at the root.

4. **MUST NOT drop coverage to make red go away.** After deletion, `erlmcp_server_session`
   **MUST** still be ≥90% via the SUITE alone. If removing the file would drop a
   real path below the floor, that path was unique → it belongs in the fold-list
   (item 1).

5. **MUST disclose the consolidation** in the closing report and the ledger Notes:
   a short list of which `erlmcp_session_tests` cases were **folded** (and where)
   vs **dropped as redundant** (and why). No silent drops.

6. **MUST close the still-open gate rows** (carried from iter-3):
   - **P6M1-14:** `rebar3 as test cover -v --min_coverage=90` exits **0**. Cover the
     in-scope modules (`erlmcp_client_session` per iter-3, the spine modules); scope
     `cover_excl_mods` for out-of-scope/doomed modules **with a named re-entry in the
     ledger** — at minimum `erlmcp_transport_streamable_http` (deleted in P6-M3). No
     silent exclusions; do not exclude `erlmcp_server_session`/`erlmcp_client_session`/
     `erlmcp_registry` as a shortcut.
   - **P6M1-17:** CI green on the **pushed** branch.
   - **P6M1-18 / P6M1-19:** conformance suite green at the **intact 87.5%** bar;
     client side passing against the new core.
   - **Align `make check` with CI:** add `--min_coverage=90` to the `check`/`test`
     path so the local gate matches CI. This iteration surfaced that `make check`
     passes while the CI cover gate fails — local and CI must not diverge on the
     coverage floor.

7. **MUST NOT lower any threshold** (the 90% gate or the 87.5% conformance bar) and
   **MUST NOT redesign the accepted P6-M1 modules** (`erlmcp_server`, `erlmcp_reply`,
   the responder seam, the behaviour, the session structure). This pass is test
   consolidation + closing the gates. A real bug surfaced by a folded test may be
   fixed (and noted) — that is the only production-code change permitted.

8. **MUST complete the 19-row ledger walk.** Final Status + Evidence (commit SHA +
   Verify output) for every row P6M1-1…P6M1-19. Per-row walk, no prose summary,
   name any uncertainty.

## Verify (the ledger Verify commands)

- `rebar3 eunit` → 0 failures, **0 cancelled**; `erlmcp_session_tests` no longer
  exists (`! ls test/erlmcp_session_tests.erl`).
- `rebar3 eunit --module=erlmcp_conformance_tests` → 0 failures/cancelled; scores ≥ 87.5%.
- `rebar3 as test cover -v --min_coverage=90` → exit 0; `erlmcp_server_session` and
  `erlmcp_client_session` ≥90%; every `cover_excl_mods` entry has a ledger re-entry note.
- `rebar3 compile` warning-free; `rebar3 xref`, `rebar3 dialyzer` clean; `rebar3 proper -c` green.
- `make check` exits 0.

## Working protocol

- **Branch:** continue on `task/0.6.0-p6m1`; PR into `release/0.6.x`.
- **Commit coherently** (audit+fold; deletion; gate scoping), updating ledger rows in-commit.
- **Iteration cap — this is iteration 4 of 5.** If the audit reveals the SUITE has
  *substantial* real gaps (i.e. `erlmcp_session_tests` was covering a lot the SUITE
  does not), fold what's cheap, then **stop and raise to CDC** with the remaining
  gap rather than spending iteration 5 blindly — that would signal the SUITE itself
  was under-built and needs a scoped follow-up, not more grinding.
- **Raise, don't route around.** Anything that can't close cleanly gets a disclosed
  amendment with a named re-entry — never a lowered bar or a silent exclusion.

## Done when

`erlmcp_session_tests` is gone with its unique coverage folded into the SUITE and
disclosed; `rebar3 eunit` is 0/0 (no cancellations); the conformance suite is green
at 87.5%; the coverage gate exits 0 with `erlmcp_server_session` and
`erlmcp_client_session` ≥90% and every exclusion disclosed; `make check` exits 0;
and all 19 ledger rows carry a final Status + Evidence for CDC re-review.
