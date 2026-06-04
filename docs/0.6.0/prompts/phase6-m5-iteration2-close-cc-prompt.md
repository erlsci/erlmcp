# CC Prompt — P6-M5 iteration 2 (write inbound, reframe drift, test the testable, walk honest)

> Imperative brief for **CC**. Focused close pass for P6-M5. Iteration 2 of 5.
> Iter-1 delivered the schema, the SHOULD⇒MUST overlay, the three regression
> CTs, the outbound validator, and the jesse-on-draft-06 amendment cleanly —
> good substantive work. The architectural seam held (empty diff on
> `erlmcp_server_session.erl` in `f6f6561`). This iteration closes the **headline
> criterion that didn't land** (inbound validation), reframes one deferral into
> a real `done` against amended criterion, tightens the coverage ceiling to
> what's *actually* untestable, and cleans up disposition vocabulary. Every item
> is a **MUST**. Read all of it before editing.

## Important context — read this first

**The "don't touch session core" rule in the M5 prompt was scoped to the
session's *dispatch logic and responder seam* — the architectural firewall held
across M2/M4/M5.** It was **not** scoped to:

- every line of `erlmcp_server_session.erl` (you can add a small chokepoint
  call there if the design genuinely requires it), and
- not at all to **`erlmcp_json_rpc`**, which is a separate module that already
  owns `decode_and_classify` — a natural place to add inbound validation.

**The prompt told you to *escalate before touching* if a P6-M5 requirement
seemed to need the spine touched — that means *stop and ask CDC/Duncan for a
decision*, not "decide it's out of scope and defer."** Iter-1 deferred P6M5-4
on this misreading. We're correcting it now: inbound validation lands in
`erlmcp_json_rpc` (no session-core touch needed), and the row closes as `done`.

The same misreading shows up in the disposition vocabulary — "done with caveat"
and "done (amendment)" sound similar but only one is a valid LEDGER_DISCIPLINE
final state. **`done` against an amended criterion is correct.** "Done with
caveat" is not. We fix that too.

## MUSTs

### 1. MUST write inbound validation — in `erlmcp_json_rpc`, not the session

`erlmcp_json_rpc:decode_and_classify` is the natural chokepoint: it already
inspects the envelope on every inbound message and runs *outside* the session.
**Add schema validation there**, using the existing `erlmcp_schema:validate/2`
jesse wrapper. The session does not need to be touched. The architectural seam
stays intact.

Concretely:

- After successful decode, validate the **envelope** against the schema's
  JSON-RPC request/notification/response definitions. On failure: return a
  classified result that the session translates to JSON-RPC **`-32600`**
  (Invalid Request).
- For requests with method-specific param schemas (e.g. `initialize`,
  `tools/call`, `resources/read`), validate the **`params`** field against the
  method's definition. On failure: classify as `-32602` (Invalid params).
- The error response the session emits in either case **must itself pass
  outbound validation** (otherwise we ship a malformed error about a malformed
  request — same class of defect).
- Use only `erlmcp_schema:validate/2` — no parallel validator (P6M5-10).

Add `test/erlmcp_inbound_validation_SUITE.erl` with at minimum:

- `envelope_missing_jsonrpc_field` → `-32600`.
- `envelope_wrong_jsonrpc_version` → `-32600`.
- `valid_envelope_bad_params` (e.g. `initialize` missing `protocolVersion`) →
  `-32602`.
- `error_response_is_schema_valid` (drive a `-32600` and a `-32602`, run the
  emitted response back through outbound validation, assert it passes).

**Close P6M5-4 as `done` against the (unchanged) criterion.** No amendment
needed — the criterion was always satisfiable, the deferral was a misreading.

### 2. MUST reframe P6M5-9 — drift-guard `done` against amended criterion

The drift *risk* exists regardless of how the schema is produced — `schema.ts`
can change and `priv/schema/mcp-2025-11-25.json` can fall out of sync silently.
"Wait for a generator" is not a re-entry condition; it's an open hole.

Pick **one** of these two cheap mechanisms and implement it:

- **(a) Version-match CI step.** A CI job parses both `priv/schema/mcp-2025-11-25.json`
  and `docs/0.6.0/planning/schema.ts` and asserts the protocol-version string
  matches (e.g. `2025-11-25`). If they diverge, fail CI. Trivial to implement
  (~10 lines of shell or a tiny script). Catches the case where the version is
  bumped in one file and not the other.
- **(b) Companion-edit CI guard.** A CI step (or git-hook spirit, encoded as a
  CI check) fails the job if a commit edits `docs/0.6.0/planning/schema.ts`
  without also editing `priv/schema/mcp-2025-11-25.json`. Catches more cases
  than (a) but is slightly more script.

Either is acceptable. **(a) is the cheaper, more deterministic option — pick
it unless (b) is meaningfully better in your judgement.**

Document the chosen mechanism in `priv/schema/README.md`. Update P6M5-9's
**criterion text** in the ledger to match what you implemented (it currently
says "regeneration-based drift check"; rewrite to the version-match-or-
companion-edit form you chose). Mark the row **`done`** against the amended
criterion — not `deferred`.

### 3. MUST test the cheaply-testable lines for P6M5-13 — then close honestly

The iter-1 amendment marked all of `erlmcp_schema`'s uncovered lines as a
"genuine ceiling." Some are not — they're easily exercised with bad inputs:

- **`find_existing/1`** at L176–186 (the `{error, schema_file_not_found}` tail
  when no candidate path exists) — a one-line unit test that passes
  `["/no/such/path"]` covers it. Not a ceiling.
- **Schema file decode error paths** at L139–148 (malformed JSON) — write a
  fixture file containing `not valid json`, pass its path to the loader, assert
  `{error, _}` comes back. Not a ceiling.
- The same shape on `erlmcp_codec` L84/L89 (non-map input guards) — pass a
  binary or atom; assert it errors cleanly. Not a ceiling.

**MUST: read the cover report line-by-line, write the cheap tests for the
testable ones, then look at what's left.** Bet: `erlmcp_schema` rises from 82%
to ≥90% without an amendment at all, and `erlmcp_codec` from 88% to ≥90%
likewise.

If after those tests anything remains below 90%, **name the residual lines
with per-line reasons** (the M2 stdio_sup / M4 http_sup pattern), and close
P6M5-13 as **`done`** against an amended criterion with the named-ceiling list.
**Not** "done with caveat" (not a valid LEDGER_DISCIPLINE final state).

### 4. MUST clean up disposition vocabulary on the walk

LEDGER_DISCIPLINE valid final states are **`done` / `deferred` / `no-op`**.
Variations like "done with caveat", "done (with caveat)", "superseded",
"deferred (partial)" are not valid finals. **`done` against an amended
criterion** is fine — that's the form M4 used and the form to keep here.

For every row, set a single final state, then put any nuance in the **Notes
column** (where it belongs). The closing tally line at the bottom of the
ledger must add up to the row count (M4 iter-2 was 19+2+1 = 22 on a 21-row
ledger — arithmetic-typo class; check yours).

### 5. MUST keep every other gate green

- `make check` exits 0.
- `make dialyzer` clean on 27 *and* 28 with zero suppressions (same as iter-1;
  the OTP 27 leg closes when CI's 27 leg runs).
- The session core stays untouched (verify with `git show <commit> -- src/erlmcp_server_session.erl`
  before declaring iteration 2 complete — empty output = held).
- No new suppressions added (`! grep -rnE "nowarn\|-dialyzer\(" src`).

### 6. MUST push for CI

P6M5-14 (dialyzer-on-27) and P6M5-15 (matrix CI green) retire together when
the branch is pushed and the workflow reproduces. No code change for these;
just the push, once 1–5 are in.

## Verify (the ledger Verify commands)

- `grep -nE "erlmcp_schema:validate" src/erlmcp_json_rpc.erl` shows the inbound
  call site.
- `rebar3 ct --suite erlmcp_inbound_validation_SUITE` passes the four named CTs.
- Drift-guard mechanism implemented + documented in `priv/schema/README.md`;
  P6M5-9 criterion text updated to match.
- `rebar3 as test cover -v --min_coverage=90` exits 0 with per-module figures
  for `erlmcp_schema` and `erlmcp_codec` recorded.
- All 15 ledger rows have a single valid final state (`done` / `deferred` /
  `no-op`); closing tally adds up to 15.

## Iteration cap

This is iteration 2 of 5. The remaining items are all small and bounded —
inbound wiring at a named chokepoint, picking and implementing one of two
named drift mechanisms, writing cheap unit tests for testable lines, and
fixing disposition vocabulary. If any of these unexpectedly balloons (e.g. the
inbound chokepoint genuinely can't be cleanly added to `erlmcp_json_rpc`),
**stop and escalate with specifics** — and "escalate" means *stop and tell
CDC/Duncan*, not *decide and defer*.

## Done when

Inbound validation is wired in `erlmcp_json_rpc` and tested for `-32600` and
`-32602` (the error responses themselves passing outbound validation); P6M5-9
has a real drift-guard mechanism implemented and the criterion text matches;
P6M5-13's testable lines have tests and the residual is a named-ceiling
amendment (or no amendment at all); every row has a single valid final state;
`make check` green, dialyzer clean on 28 (27 via CI), session core empty-diff;
CI green on the pushed branch. **Then M5 is genuinely closed: 15 of 15, no
softpedalled deferrals, headline criterion shipped.**
