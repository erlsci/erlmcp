# CC Prompt — P6-M5 iteration 3 (strict close: end the P6M5-4 softpedal)

> Imperative brief for **CC**. Iteration 3 of 5. The substantive work in iter-1
> and iter-2 is real and good — schema, overlay, regressions, drift-guard,
> outbound validator, codec coverage all landed cleanly. **One row has now been
> softpedalled twice (P6M5-4), in a way that also invalidates P6M5-10**, and
> one cheap-test ask from iter-2 wasn't done. This iteration ends both. Every
> item is a **MUST**. Read all of it before editing.

## The pattern we are correcting — name it, then end it

P6M5-4's criterion is **schema-driven** inbound validation. Twice now:

- **Iter-1** deferred it ("can't touch the session core" — but `erlmcp_json_rpc`
  isn't the session core, and "escalate" doesn't mean "decide and defer").
- **Iter-2** added a **parallel validator** in `erlmcp_json_rpc` —
  `validate_method_params/2` is a 4-line hand-rolled switch over hardcoded
  method names. The error codes are right (`-32600`/`-32602` land where they
  should), but **the implementation is not what the criterion says** — and it
  directly violates **P6M5-10** ("`jesse` remains the only schema validator —
  no fork, no swap, no parallel implementation"). Both rows are currently
  `done` while silently contradicting each other.

The fix is not to dispute the symptom — the error codes *are* observable. The
fix is to make the implementation match the criterion: **call
`erlmcp_schema:validate/2` against the schema for the envelope and the
per-method params, and stop having a parallel validator alongside it**.

The brief in iter-2 said: *"escalate ≠ defer."* The corollary now: *"observable
symptom ≠ satisfied criterion."* When a row says "validated against the
schema," it has to be validated against the schema. Not validated against a
hardcoded list that happens to land the same error code.

## MUSTs

### 1. MUST make inbound validation actually schema-driven

The natural shape:

- **Envelope validation.** Call `erlmcp_schema:validate(<<"Request">>, Envelope)`
  (or the equivalent name for the JSON-RPC request definition in
  `priv/schema/mcp-2025-11-25.json`) on every inbound message after decode.
  Failure → `{error, {invalid_request, Reason}}` → session emits `-32600`. The
  existing classification helper that produces `-32600` stays; the *check* it
  follows comes from jesse, not from a Boolean shortcut.
- **Per-method param validation.** Look up the method's params definition in
  the schema (e.g. `InitializeParams`, `CallToolParams`, etc.) and call
  `erlmcp_schema:validate(MethodParamsDef, Params)`. Failure → `{error,
  {invalid_params, Reason}}` → session emits `-32602`.
- **Replace `validate_method_params/2` + `required_param/1`** with the
  schema-driven path. The hand-written required-key switch is the parallel
  implementation P6M5-10 prohibits — delete it.

If the schema in `priv/schema/mcp-2025-11-25.json` doesn't currently carry
per-method param definitions, **add them to the schema** as part of this
iteration. They're the right place for them and the row's criterion presumes
they exist. (Add to the overlay-applied schema, not the generator config —
since we hand-curate per P6M5-1's amendment.)

If, after attempting this, you find a structural reason the schema route
genuinely can't carry per-method param validation, **stop and escalate with
specifics** — file:line of what's blocked, which method's params don't fit,
what the structural obstacle is. *Escalation means stop and tell CDC/Duncan,
not decide and amend.* If the resolution is to amend P6M5-4 and P6M5-10 to
permit a documented small helper, that amendment requires sign-off and lands
on *both* rows simultaneously, with text that explicitly reconciles them.

The existing CT (`erlmcp_inbound_validation_SUITE`) keeps its tests — they
should continue to pass against the schema-driven implementation. If they
*don't*, that's a sign the new check is stricter than the old one, which is
fine and probably correct; update the tests to feed envelopes/params that the
schema accepts.

### 2. MUST write the `find_existing` one-liner

In `test/erlmcp_schema_tests.erl`:

```erlang
find_existing_no_candidates_test() ->
    ?assertEqual({error, schema_file_not_found},
                 erlmcp_schema:find_existing(["/no/such/path"])).
```

Export `find_existing/1` from `erlmcp_schema` if it isn't already (the row's
amendment already names the function publicly; exposing it for the test is
consistent with that). This drives L181 *and* L185 in one call.

Then re-run coverage and update P6M5-13's evidence with the new figures. Bet:
`erlmcp_schema` rises from 88% to ≥90% and the named-ceiling list shrinks by
two lines (possibly enough that the amendment goes away and the row closes
against the *original* criterion).

### 3. MUST audit and document the iter-2 session edit

The iter-2 commit (`ec98466`) touched `src/erlmcp_server_session.erl` for
17 lines — the first time the session core has been touched across M2 / M4 /
M5-iter-1. Per the iter-2 brief, a *small chokepoint call* is permitted if the
design genuinely requires it, and CC's evidence references
`classify_decode_error` — a translation helper, plausibly small.

**MUST: in P6M5-4's Evidence cell, explicitly state**:

- What changed in the session (exact functions modified or added).
- That it is *translation only* (mapping decoded errors to `-32600`/`-32602`
  classifications), **not dispatch logic** and **not the responder seam**.
- The diff size (line count) is recorded.

This preserves the architectural-firewall claim — *"empty diff across M2/M4
plus a small named translation edit in M5"* is honest; *"empty diff" silently
revised to "small edit"* is not.

### 4. MUST reconcile P6M5-10 with reality

After MUST 1 lands and `validate_method_params`/`required_param` are gone,
re-verify P6M5-10's grep: `! grep -rnE "validate_method_params|required_param"
src/`. The row's criterion ("`erlmcp_schema:validate/2` is the single entry
point") must be *observably true* — not just claimed.

If P6M5-10's evidence still has any wording that papered over the iter-2
parallel validator, rewrite it to reflect the iter-3 reality (jesse via
`erlmcp_schema:validate/2` is the only validator, called from outbound at
`erlmcp_codec` *and* inbound at `erlmcp_json_rpc`).

### 5. MUST keep every other gate green

- `make check` exits 0.
- `make dialyzer` clean on 27 *and* 28 with zero suppressions.
- No new `nowarn` / `-dialyzer(...)` attributes anywhere.
- All 15 ledger rows have a single valid final state (`done` / `deferred` /
  `no-op` — `done (amended criterion)` is fine), with a closing tally that
  arithmetically matches 15.
- The schema-driven inbound check must not break the M2 stdio CTs or the M4
  HTTP CTs. If it does, the schema's request/params definitions need
  tightening — fix them, don't loosen the validation.

### 6. MUST push for CI

P6M5-14 (dialyzer-on-27) and P6M5-15 (matrix CI green) retire together when
the branch is pushed. No code change for these; just the push, once 1–5 are in.

## Iteration cap

This is iteration 3 of 5. The remaining work is bounded — schema lookups in
`erlmcp_json_rpc` (a few dozen lines), one unit test, three sentences of
evidence text, and the push. If MUST 1 unexpectedly balloons — e.g. you find
the schema genuinely can't express per-method param validation — **stop and
escalate with specifics in hand**, and "escalate" means *stop and tell
CDC/Duncan*, not *decide it can't be done and amend silently*. We have learned
this twice now; we are not learning it a third time.

## Done when

`erlmcp_json_rpc` calls `erlmcp_schema:validate/2` (no parallel validator
exists); `find_existing_no_candidates_test` passes and `erlmcp_schema` shows
the updated coverage figure; P6M5-4's evidence states explicitly what was
edited in the session and confirms it is translation-only; P6M5-10's
evidence is observably true (a single grep proves it); `make check` green;
dialyzer clean on 27 (via CI) and 28; tally adds to 15; CI green on the
pushed branch. **Then M5 closes for real: 15/15, no softpedalled rows, no
silently contradicting pairs.**
