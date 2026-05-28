# CC Prompt — Strict-dialyzer fixes (triaged decisions)

> Imperative brief for **CC**. The 48-warning inventory you produced has been
> triaged by CDC + Duncan. This is the fix pass: each category below carries a
> **decision** — implement it. `underspecs` has been **dropped from the gate**
> (CDC edited `rebar.config`), which removes ~24 warnings that were intentional
> API breadth, not defects. Run dialyzer on **OTP 27 AND 28** (see the gate note
> at the end — 27 is the version that actually catches opacity). Every item is a
> **MUST**. Escalate new judgment calls; do not suppress.

## Prerequisite

0. **Revert the opaque demotion.** Restore `erlmcp_server.erl`'s `server()` to
   `-opaque server() :: pid()` (and any peer type demoted to `-type` to appease
   25/26). The 27+ gate + un-suppressed `opaque` warning support opaque types
   correctly now; the `is_pid`-on-opaque guards that caused the original failure
   are already gone, so this should stay clean on 27. C5 below depends on this.

## Fixes by category

**C1 — start_link specs missing `ignore` (14).** Use the **OTP-provided return
types**, not a hand-written `| ignore`:
- `gen_server` wrappers → `gen_server:start_ret()`
- `gen_statem` wrappers → `gen_statem:start_ret()`
- `supervisor` wrappers → `supervisor:startlink_ret()`
Apply to all 14 sites (incl. the `streamable_http` stub — two trivial lines, fix
rather than exclude). This is type-honest and self-documenting.

**C2 — supervisor `start_child` wrappers (2): narrow, don't widen.** In
`erlmcp_task_sup:start_task/1` and `erlmcp_transport_sup:start_child/3`, `case` on
the `supervisor:start_child/...` result and return a clean
`{ok, pid()} | {error, term()}` to callers — do **not** widen the spec to leak
`{ok, undefined | pid(), _}`. These workers are never `undefined`; present a tidy
contract, don't expose supervisor internals.

**C3a — `erlmcp_json_rpc:parse_response/3` extra_return.** Confirm malformed
responses are genuinely handled **upstream** (in `decode_and_classify`). If yes →
tighten the spec to `{ok, _}`. If **no** → the missing `{error,_}` path is a real
gap, not a spec typo — **stop and escalate** rather than tightening over it.

**C3b — `add_tool/2` extra_return → add validation (Duncan's decision).** The
spec promises `ok | {error,_}` but `erlmcp_server:register_tool/2` can't fail —
i.e. registration silently accepts malformed tool specs. Fix the **code, not the
spec**: add registration-time validation in `erlmcp_server:register_tool/2`
(required keys present + correct types — proportionate structural validation,
*not* full MCP-schema/jesse validation, which is P6-M5), returning
`{error, {invalid_tool_spec, Reason}}` on bad input. Fail loud at registration,
not at protocol time — this closes the silent-acceptance class that caused the
original icon/`taskSupport` bugs.
- **Escalate, don't assume:** whether `register_resource`/`register_resource_template`/
  `register_prompt` should *also* validate + return `{error,_}` for consistency is
  a contract change (their specs are currently `-> ok`). Do `add_tool` now; raise
  the register_* family consistency question to CDC/Duncan rather than silently
  changing all their contracts in this pass.

**C4 — underspecs: gate flag dropped; tighten only PRIVATE specs as hygiene.**
Do **not** chase the public-API ones — `content()` and `schema()` stay `map()`;
`erlmcp_capabilities:supported_versions/0` stays `[binary()]`;
`erlmcp_instructions:generate/1` stays `binary()`. Those specs are correct.
Voluntarily tighten the **internal/private** specs where it's a clear improvement
and has zero API-stability cost:
- `erlmcp_uri_template:match/2` → `{ok, #{binary() => binary()}}`
- `erlmcp_codec:encode/1` error → `{error, invalid_utf8 | {encode_error, badarg}}`
- the `erlmcp_json_rpc` internal helpers and `transport` private helpers → their
  real shapes.
If any of these turns out to be public/exported and the broad type is intentional,
leave it and note why.

**C5 — opaque type in setup-function return specs (3).** In `erlmcp.erl`:
`start_stdio_setup/2`, `start_tcp_setup/3`, `start_http_setup/3` — change the map
spec key `server := pid()` to `server := erlmcp_server:server()`, and add the
missing `transport_id` key to `start_tcp_setup/3`'s return. (Depends on step 0.)

**C6 — fix the real bugs.**
- `erlmcp_transport_http:calculate_retry_delay/2`: it can return `float()` but the
  spec (and timer usage) want `pos_integer()` — fix the **code** to produce integer
  milliseconds (`round/1` or `trunc/1` the backoff), not just the spec. A float
  delay handed to timer functions is a latent runtime bug.
- The two remaining internal `underspecs` (`process_response/1`, `process_raw_input/1`)
  are moot now the flag is dropped; tighten only if they're private and trivial.

## Gate & discipline

- **Run `make dialyzer` on BOTH OTP 27 and 28** and confirm clean on each. 27 is
  the version that catches opacity violations; passing only on 28 is not enough.
  Keep the full 25–28 matrix green on the non-dialyzer steps; `make check` green.
- **No suppressions.** No re-adding `no_*`, no `-dialyzer(...)` attributes, no
  `any()`-laundering of specs. If you hit a genuine false positive on 27/28, name
  it precisely (file:line + why) and escalate for a decision — don't bury it.
- **Escalate new judgment calls** (the register_* consistency question; a
  `parse_response` missing-path if it turns out real; anything that changes public
  API or behaviour). Mechanical fixes: just do them. This completes P6-M1's
  dialyzer cleanliness (P6M1-15) under the strict bar and unblocks CI (P6M1-17).

## Done when

`server()` is opaque again; `make dialyzer` is clean on OTP 27 **and** 28 with the
strict warning set and zero suppressions; `add_tool` validates and the silent-
acceptance gap is closed; the real `calculate_retry_delay` bug is fixed; the full
matrix is green on non-dialyzer steps; and any new judgment-call finding has a
recorded disposition rather than a suppression.
