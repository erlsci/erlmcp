# CC Directive — registration validation consistency

> Short follow-up to the strict-dialyzer pass. Decision (Duncan, via CDC): extend
> the registration-time validation you added to `register_tool/2` to the sibling
> registration functions, so the whole family fails loud on malformed input
> instead of just tools. Validate at the edge; one way to do a thing.

## Do

Mirror `register_tool/2`'s pattern for the other three registration entry points
in `erlmcp_server.erl`:

- `register_resource/2`
- `register_resource_template/2`
- `register_prompt/2`

For each: validate the spec **before** the `gen_server:call`, returning
`{error, {invalid_<kind>_spec, Reason}}` on malformed input
(`invalid_resource_spec`, `invalid_resource_template_spec`, `invalid_prompt_spec`).

1. **Factor a shared validator — do not copy-paste four times.** A common helper
   (e.g. `validate_spec(Kind, Map)` over a per-kind required-keys table, or
   per-kind functions delegating to one checker) so the logic lives in one place
   alongside `validate_tool_spec/1`. Keep the **same depth of rigor** as
   `validate_tool_spec/1` — proportionate **structural** validation (required keys
   present + correct types). This is *not* MCP-schema/jesse payload validation —
   that's P6-M5.

2. **Required keys** per the MCP model — confirm against `erlmcp_model` / the
   schema rather than guessing, but expected to be roughly: resource → `uri`;
   resource_template → `uriTemplate`; prompt → `name` (plus type checks on those).

3. **Widen the specs to match the new contract**, both in `erlmcp_server.erl` and
   the facade wrappers in `erlmcp.erl` (`add_resource/2`,
   `add_resource_template/2`, `add_prompt/2`), from `-> ok` to
   `-> ok | {error, {invalid_<kind>_spec, term()}}`. (Well-formed callers still get
   `ok`; only malformed input hits the error path.)

4. **One test per kind**: a malformed spec returns `{error, {invalid_<kind>_spec, _}}`,
   and a well-formed spec returns `ok`. Assert on the error tag, not just non-`ok`.

## Don't

- No copy-pasted validators; no validation deeper than tool's (no jesse here).
- No suppressions; if a widened spec trips dialyzer, fix the spec/code, don't
  `-dialyzer` around it.

## Done when

All four registration entry points validate consistently through the shared
helper; facade + server specs widened to match; one passing test per kind;
`make check` green and `make dialyzer` clean on **OTP 27 and 28**.
