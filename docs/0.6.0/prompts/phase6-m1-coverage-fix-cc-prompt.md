# CC Prompt — Phase 6 / P6-M1 iteration 2 (coverage fix, P6M1-14)

> Imperative brief for **CC**. This is a **focused iteration-2 correction**, not a
> new milestone. CDC reviewed commit `348b51b` and accepted 16 of 17 rows; this
> closes the one open row (P6M1-14) and completes the ledger walk CC owes.
> Iteration budget: this is **iteration 2 of 5** on the P6-M1 ledger.

## What's wrong

`erlmcp_server_session` sits at **72%** line coverage; the gate is **90%**
per-module (`cover_excl_mods=[]`, correctly). So `rebar3 as test cover
--min_coverage=90` fails on the session. CDC **rejected** the deferral that
parked this at P6-M5: per `CLAUDE.md`'s coverage rule, "tested via example suites
not running in this config" is the **covered → write the test** case, not a valid
deferral; the amendment also named no specific uncovered lines; and P6-M5
(examples rehabilitation) rewrites example servers — it will not add core-session
coverage to the gate.

## What to do

The uncovered code is **core protocol surface** that ships in the session module
now and must be driven by **core** tests, not example suites. Bring
`erlmcp_server_session` to **≥90% in the gating config** by exercising, from
`test/erlmcp_server_session_SUITE.erl`, the handlers currently unexercised there:

- `resources/read`, `resources/subscribe`, `resources/unsubscribe`,
  `resources/templates/list`
- `prompts/get`
- `completion/complete`
- `tasks/get`, `tasks/list`, `tasks/result`, `tasks/cancel`

Drive them by registering **stub** handlers/resources/prompts/tasks on an
`erlmcp_server` and sending the corresponding requests through a session with a
stub responder (the test-pid `{send, Json}` pattern already used in the suite).
Assert on the responses that come back to the responder — not just that the call
returns — so the tests would fail if the handler logic were wrong (no vacuous
tests).

Two rules from `CLAUDE.md` apply while you do this:

1. **Dead code is deleted, not tested.** The catalog-removal refactor (720-line
   session delta) may have left unreachable branches. If a branch genuinely cannot
   be driven from any request in the new architecture, **delete it** and note what
   you removed — dead code in this repo has twice hidden real defects. Do not write
   a test that only exists to touch a dead line.
2. **A genuine ceiling names exact lines.** If, after writing the core tests and
   deleting dead branches, specific lines remain provably unreachable, list them
   line-by-line in the P6M1-14 row with the reason — that is the only acceptable
   sub-90 disposition. Do **not** re-add the module to `cover_excl_mods` and do
   **not** lean on the example suites.

## Also owed: the ledger walk

The ledger (`docs/0.6.0/milestones/phase6-m1-core-spine-ledger.md`) arrived with
every row still `open` and no Evidence. Complete the per-row walk: for **all 17
rows**, set the final Status and fill Evidence (commit SHA + the Verify command's
output). CDC has pre-filled its independent dispositions in the "CDC Review —
Iteration 1" block; reconcile your evidence against it. Do not write a prose
summary in place of the per-row walk.

## Do not touch

The other 16 rows' implementation is accepted — do not refactor `erlmcp_server`,
`erlmcp_reply`, the responder seam, the behaviour, or the session's structure.
This iteration adds **tests** (and deletes any dead code they expose); it does not
redesign. If a test reveals a real behavioural bug, fix the bug and note it — but
that is the only code-path change permitted here.

## Gates (all must hold)

- `rebar3 as test cover -v --min_coverage=90` passes — `erlmcp_server_session`
  included and ≥90% (per-module, not just aggregate).
- `rebar3 compile` warning-free; `rebar3 xref`, `rebar3 dialyzer` clean.
- `rebar3 eunit` + Common Test green; `rebar3 proper -c` green.
- CI green on `task/0.6.0-p6m1`.
- All 17 ledger rows have a final Status + Evidence; P6M1-14 is `done` (or, if a
  real ceiling, sub-90 with exact named lines).

## Done when

The coverage gate passes with the session included, the ledger is fully walked and
evidenced, and the branch is green on CI for CDC re-review.
