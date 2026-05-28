# CC Prompt — Strict-dialyzer hardening pass

> Imperative brief for **CC**. This is a cross-cutting toolchain-hardening task,
> run as a **team**: you work the trenches (surface and fix what strict dialyzer
> finds); **CDC + Duncan** adjudicate the design/spec judgment calls. The goal is
> not just "green" — it's to *uncover* the real issues the old suppressions were
> hiding. Surfacing a hard finding is success, not failure.

## What changed (infrastructure, already done by CDC)

- **`rebar.config` dialyzer is now strict:** every `no_*` suppression removed
  (so `opaque`, `match`, `fail_call`, `contracts`, `behaviours`,
  `undefined_callbacks`, `fun_app`, `improper_lists` are all reported again),
  plus opt-in `underspecs`, `extra_return`, `missing_return` added.
- **Dialyzer is gated to OTP 27+** (the `dialyzer` target in the `Makefile`
  detects the OTP release and skips on 25/26, where opaque analysis false-positives).
  So run dialyzer on **OTP 27 or 28**. compile/xref/eunit/ct/proper/cover still
  cover the full 25–28 matrix.

## MUSTs

1. **Revert the opaque demotion.** Restore `erlmcp_server.erl`'s `server()` to
   `-opaque server() :: pid()` (and any other type demoted to `-type` to appease
   25/26). The 27+ gate + the un-suppressed `opaque` warning now support opaque
   types correctly — keep the house-style encapsulation ("opaque types + accessor
   functions"). Do **not** leave `-type` aliases that were only demoted to dodge
   old dialyzer.

2. **Inventory before you fix.** Run `make dialyzer` on OTP 27, capture the
   **full** warning list, and categorize it (opacity / contracts / underspecs /
   extra_return|missing_return / unmatched_returns / behaviours / other) before
   touching code. Post the inventory — that categorized list is the first
   deliverable, and it tells CDC where the real findings are.

3. **Fix at the root, never suppress.** No re-adding `no_*` to `rebar.config`, no
   `-dialyzer(...)` attribute suppressions, no `-spec ... any()` laundering, no
   widening a return type just to silence a warning. Opacity violations → respect
   the boundary (accessors, don't `is_pid`/pattern-match internals outside the
   defining module). `underspecs` → tighten the spec to the real success typing.
   `extra_return`/`missing_return` → make the spec and the code agree (decide which
   is wrong). `callback`/`behaviour` warnings → implement/fix the callback.

4. **Escalate the judgment calls — this is the teamwork seam.** When a warning is
   *mechanical* (a spec typo, a missing clause), just fix it. When a warning
   reveals a **design or intent question**, STOP and report it to CDC with the
   specifics rather than guessing — e.g.:
   - an `underspecs` warning where the broad spec might be intentional API surface;
   - an opacity tension where respecting the boundary needs a new accessor;
   - a `no_return`/`extra_return` that hints the success typing disagrees with the
     intended contract;
   - anything where the "fix" would change observable behaviour or public API.
   Surface these as a short list with file:line + your read of the tradeoff. CDC +
   Duncan decide; you implement the decision.

5. **Keep everything else green.** `make check` on OTP 27/28 must end clean
   (compile warning-free, xref, dialyzer, eunit/ct/proper, cover ≥90%); the full
   25–28 matrix must stay green for the non-dialyzer steps.

## Working protocol (teamwork)

- Work on the current P6-M1 branch (`task/0.6.0-p6m1`) unless CDC says otherwise —
  this completes P6-M1's dialyzer cleanliness (P6M1-15) under the strict bar and
  unblocks CI (P6M1-17).
- **Two deliverables, in order:** (1) the categorized warning inventory (post it,
  don't fix yet); (2) after CDC/Duncan triage, the fixes — mechanical ones done
  directly, judgment-call ones per the decisions returned to you.
- Commit in coherent groups; note in each commit which warning category it closes.
- **Don't rush to green.** A suppressed or laundered warning is worse than an open
  one — it re-hides what we just paid to uncover. If you're tempted to widen a
  spec or suppress, that's exactly the signal to escalate instead.

## Done when

`server()` (and peers) are opaque again, `make dialyzer` is clean on OTP 27 and 28
with the strict warning set and zero suppressions, the full matrix is green on the
non-dialyzer steps, and every judgment-call finding has a recorded
disposition (fixed-as-decided / accepted-with-rationale) rather than a silent
suppression.
