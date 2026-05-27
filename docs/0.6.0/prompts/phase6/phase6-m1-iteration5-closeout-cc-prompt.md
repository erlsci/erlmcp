# CC Prompt — Phase 6 / P6-M1 iteration 5 (closeout)

> Imperative brief for **CC**. Single focused task to close P6-M1. **Iteration
> budget: this is iteration 5 of 5 — the cap.** Everything else is verified and
> green; this pass exists only to bring `erlmcp_client_session` to the floor and
> close the ledger. Every item is a **MUST**.

## The one gap

`erlmcp_client_session` is at **88%**, below the **90%** per-module floor that
P6M1-14 requires for the in-scope set. Duncan's call: **close it now** — do not
defer. (The "re-entry P6-M2" note was invalid anyway: P6-M2 is the stdio transport
milestone and would never touch `client_session`.)

## MUSTs

1. **MUST bring `erlmcp_client_session` to ≥90%** with real tests that assert on
   behaviour (not call-and-ignore). The gap is ~2% — almost certainly an
   uncovered error path or a clause the existing client tests don't drive. Find the
   uncovered lines (`rebar3 cover -v` / the HTML cover report), and cover them with
   tests that would fail if that logic were wrong.

2. **MUST handle a genuine ceiling honestly, if one exists.** If any of the
   remaining uncovered lines truly cannot be driven from any test in the current
   architecture, **name the exact lines** (file + line numbers) in the P6M1-14
   evidence with the reason — that is the only acceptable sub-90 disposition. Do
   **not** re-exclude the module, lower the floor, or write vacuous tests. (At
   88→90 this should not be needed; dead lines should be **deleted**, not excused.)

3. **MUST update the ledger evidence.** Replace the `client_session` "88% /
   re-entry P6-M2" note with the closed disposition: the `rebar3 cover -v`
   per-module figures for the full P6-M1 set (`erlmcp_server`, `erlmcp_reply`,
   `erlmcp_server_session`, `erlmcp_ctx`, `erlmcp_codec`, `erlmcp_client_session`)
   each ≥90%, plus the total. Reconfirm P6M1-19 (client passes against new core)
   stays satisfied.

4. **MUST keep every other gate green.** `make check` exits 0 (with
   `--min_coverage=90`); eunit/CT/PropEr/conformance unchanged and green; the 87.5%
   conformance bar untouched; `compile`/`xref`/`dialyzer` clean. **MUST NOT** redesign
   accepted modules — add client tests only (plus a bug fix, noted, if a new test
   surfaces one).

5. **MUST push `task/0.6.0-p6m1`** so CI reproduces across the OTP 25–28 matrix —
   that closes **P6M1-17** (CI green), the last row that cannot be self-verified.

## Verify

- `rebar3 as test cover -v --min_coverage=90` → exit 0; `erlmcp_client_session` ≥90%
  in the per-module output.
- `make check` exits 0.
- All 19 ledger rows `done` with evidence (or, for P6M1-14 only, a named-line ceiling
  if one genuinely exists) — final per-row walk, no prose summary.
- CI green on the pushed branch.

## Iteration cap

This is iteration 5. Bringing 88→90 is expected to be small. If — unexpectedly —
the uncovered lines turn out to be hard or genuinely unreachable, **stop and raise
to CDC** with the exact lines rather than exceeding the cap or forcing artificial
tests. A clean named-ceiling amendment is an acceptable close; a sixth grind is not.

## Done when

`erlmcp_client_session` ≥90% (or a named-line ceiling), all 19 rows closed with
evidence, `make check` exits 0, and CI is green on the pushed branch — P6-M1 closed,
ready for CDC sign-off.
