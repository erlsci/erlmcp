# CC Prompt — P6-M4 iteration 2 (close the three softpedalled rows)

> Imperative brief for **CC**. Focused close pass for P6-M4. Iteration 2 of 5.
> The architectural achievement of iteration 1 is real and verified — empty diff
> on `erlmcp_server_session.erl` proves the session core wasn't touched, the
> stub is gone, two transports run on one spine. This iteration tightens the
> three rows that landed as `done (with caveat)` or `done (partial)` so they
> close honestly, plus the CI push that retires the matrix gates.

## The three rows + one push

### 1. P6M4-16 — write the sampling round-trip test (the big one)

The progress + cancel half of P6M4-16 is real (the `progress_over_sse` CT covers
it). The **sampling** half is *absent*: `grep` of `test/erlmcp_http_*` for
`sampling/createMessage` returns nothing. That is the headline bidirectional
contract for HTTP and it is *not* tested. M2 has the equivalent for stdio
(`erlmcp_stdio_deep_protocol_SUITE:sampling_round_trip`). M4 must have parity.

**MUST:** add `sampling_round_trip` to `erlmcp_http_deep_protocol_SUITE` (or
equivalent), driving end-to-end:

- Open a GET SSE stream against the running listener; remember the stream pid.
- POST a `tools/call` for a sampling-emitting tool (use `explain` — calculator
  example exposes it; if calculator isn't wired into your test fixture, register
  a minimal local tool whose handler does `erlmcp_ctx:request_peer(Ctx,
  <<"sampling/createMessage">>, …)`).
- On the GET SSE stream, receive the `sampling/createMessage` server→client
  request. Parse the event (id + JSON body).
- POST back a `sampling/createMessage` *response* correlated by id (a fixed
  stub reply is fine — this is testing the protocol path, not the LLM).
- Assert the originating `tools/call` response arrives correctly (whether on
  the SSE stream per the routing chosen in P6M4-5, or as the POST's
  `application/json` reply — whichever the design lands on; see #2).

The test infrastructure (SSE-parsing test client + ability to back-POST a
correlated reply) is what M2 built for stdio, just over HTTP. Bounded — a few
hundred lines of CT code at most. Don't defer this; **parity with M2 is the
bar**, and untested sampling over HTTP is the gap where a real spec bug would
slip into 0.6.0.

If you genuinely hit infeasibility, **escalate with specifics** (what blocked,
which line of code, what infrastructure is missing) rather than re-dispositioning
the row.

### 2. P6M4-5 — pin the practical question, then amend or defer cleanly

Iteration 1 routes server→client traffic through the standing **GET** SSE
stream and does *not* implement the POST-to-SSE upgrade. Both routings are
spec-MAY-compliant; the question that decides whether this is a clean
amendment-with-`done` or a deferral-with-re-entry is **what happens when a
client POSTs a fan-out request without an open GET SSE stream**:

- If the implementation gracefully degrades (delivers the result inline on the
  POST response in the no-fan-out case; or — if fan-out triggers without a
  stream — returns a defined error / queues until the next GET / declines
  cleanly), then this is an **amendment-with-`done`**. Rewrite P6M4-5 to read:
  *"Server→client traffic routes via the standing GET SSE stream while open;
  POST returns `application/json` for the originating request's result. Clients
  using sampling/progress-emitting tools are expected to maintain an open GET
  SSE stream. POST-to-SSE upgrade is a future enhancement."*
- If the implementation **hangs / loses messages / corrupts state** when a
  fan-out POST arrives with no GET stream, then it's a real conformance gap.
  Either implement the POST-to-SSE upgrade or formally `deferred` the row with
  re-entry condition *"P6-M5 (validation) or a dedicated follow-up — required
  before any spec-conformance acceptance against a client that doesn't open GET
  SSE first."*

**MUST:** write a small probe test (or a manual repro) that drives a fan-out
tool over POST with no GET stream open, then record the actual behaviour in the
ledger Notes. The disposition follows from that observation. Don't hand-wave
"spec MAY" — the spec allows both, but our row needs to reflect *which one we
chose* and what edge cases that choice covers.

### 3. P6M4-19 — name the lines per the M2 precedent

`erlmcp_http_sup` is at 73% per the cover report, and the amendment categorizes
the gap as "error branches in supervisor child wiring." That's the right
category, but the M2 stdio_sup amendment set the bar at **named lines + per-line
reason**, not category labels. Match it.

**MUST:** rewrite the P6M4-19 Notes to list the specific uncovered lines with
one-line reasons each — the likely set, from inspection of `src/erlmcp_http_sup.erl`:

- L14 (`{error, _} = Err` clause)
- L18 (`Error -> Error` tail)
- L28 (`undefined -> {error, no_listener}`)
- L32 (`{error, no_session_mgr}` clause)
- *(and any others the cover report identifies — read it, don't guess)*

For each: state whether the path is (a) testable with `meck`-style mocking but
not worth the effort (the M2 precedent), or (b) genuinely unreachable in the
current architecture — in which case **delete it** per `CLAUDE.md` ("dead code
is deleted, not excused"). If deletion gets the module to ≥90%, the amendment
goes away and the row closes against the original criterion. If it doesn't,
the amendment stands with the named lines.

### 4. Push for CI

P6M4-20 dialyzer-on-27 and P6M4-21 (matrix CI green) retire together when the
branch is pushed and the CI workflow reproduces. No code change for these;
just the push.

## Other gates (must hold)

- `make check` exits 0; `make dialyzer` clean on 27 *and* 28 with zero
  suppressions (same as iter-1).
- All 21 rows have a final Status + Evidence. **Count the actual rows in the
  ledger file before declaring the walk complete** — recurring lesson.
- The session-core seam stays held: any new code for P6M4-16's test must not
  touch `erlmcp_server_session`. If it seems to need to, **stop and escalate**.

## Working protocol

- **Branch:** continue on `task/0.6.0-p6m4`; PR into `release/0.6.x`.
- **Commit per item** (sampling test; the P6M4-5 probe + disposition; the
  P6M4-19 line-naming / deletion); update Status/Evidence in the closing commit.
- **Iteration cap:** this is iteration 2 of 5.
- **Subagents for lookup only.**

## Done when

Sampling round-trip is tested end-to-end over HTTP (or escalation with specifics
in hand); P6M4-5's disposition matches observed behaviour, not "spec MAY"
handwave; P6M4-19's amendment names lines with reasons (or deletes dead
branches and clears 90% without an amendment); `make check` green; CI green on
the pushed branch; all 21 rows walked.
