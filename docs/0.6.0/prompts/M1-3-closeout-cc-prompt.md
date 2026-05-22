# CC Prompt — erlmcp 0.6.0, M1-3 final closeout

> Imperative brief for **CC**. Small, surgical change closing the last residue
> CDC found on M1-3. Continue on `task/0.6.0-m1`. **CDC re-runs the Verify and
> reads the diff before M1-3 closes.**

## Why

M1-3's grep Verify passes, but its significance line — "no record crosses a module
boundary or appears in an exported spec" — is still violated on one legacy path:
`erlmcp_json_rpc:decode_message/1` is **exported** with a record-bearing return spec
(`decode_result()` → `json_rpc_message()` → records), and the legacy
`erlmcp_client` (M3-condemned) calls it at line ~350 and matches the returned
records across the module boundary. The new spine is already clean; this closes the
spirit of M1-3 now rather than leaving an M3 IOU. ~15 lines.

## Tasks

1. **Migrate the one legacy call site.** In `src/erlmcp_client.erl`,
   `handle_info({transport_message, Data}, State)` (≈ line 350): replace
   `erlmcp_json_rpc:decode_message(Data)` with
   `erlmcp_json_rpc:decode_and_classify(Data)` and match the tagged tuples instead
   of records:
   - `{ok, {response, Id, Result}}` → `handle_response(Id, {ok, Result}, State)`
   - `{ok, {error_response, Id, Error}}` → `handle_response(Id, {error, Error}, State)`
   - `{ok, {notification, Method, Params}}` → `handle_notification(Method, Params, State)`
   - `{error, Reason}` → keep the existing log + `{noreply, State}`

2. **Delete the now-dead private records** in `erlmcp_client.erl`:
   `-record(json_rpc_response, …)` and `-record(json_rpc_notification, …)` are used
   only by the call site above; after task 1 they are unreferenced — remove both
   definitions. (Keep `mcp_capability`, `mcp_client_capabilities`,
   `mcp_server_capabilities` — still used by the state record and capability checks.)
   Confirm with `grep -n "#json_rpc_" src/erlmcp_client.erl` → no hits.

3. **Unexport `decode_message/1`** from `erlmcp_json_rpc`: remove it from the
   `-export([...])` list. It stays as a private function (`decode_and_classify/1`
   and `decode_and_classify_any/1` call it internally). After this, no exported
   function's spec references `decode_result()` / `json_rpc_message()`, so no record
   appears in any exported spec.

4. **Re-point the one test.** `test/erlmcp_json_rpc_tests.erl` `decode_non_object_test`
   (≈ line 45) calls `erlmcp_json_rpc:decode_message(<<"[1,2,3]">>)`. Switch it to
   `erlmcp_json_rpc:decode_and_classify(<<"[1,2,3]">>)` — same `{error,
   {invalid_json, not_object}}` result (an array is not an object), so the assertion
   stands. Confirm no other caller: `grep -rn "decode_message" src test` → only
   internal uses inside `erlmcp_json_rpc.erl`.

5. **Update M1-3 evidence.** In the closing commit, append to M1-3's `Evidence`:
   `decode_message/1` unexported; legacy `erlmcp_client` migrated to
   `decode_and_classify/1`; no record appears in any exported spec and no record
   crosses a module boundary. Keep status `done`.

## Acceptance / Verify

- `! grep -rn "^-record" include/` → still 0 (unchanged).
- `grep -n "decode_message" src/erlmcp_json_rpc.erl` shows it absent from `-export`.
- `grep -rn "erlmcp_json_rpc:decode_message" src test` → no hits.
- `grep -n "#json_rpc_" src/erlmcp_client.erl` → no hits.
- Spine still clean: `for m in erlmcp_server_session erlmcp_client_session erlmcp_ctx
  erlmcp_codec erlmcp_model erlmcp_capabilities erlmcp_transport
  erlmcp_transport_stdio; do grep -n 'erlmcp\.hrl\|#json_rpc_\|#mcp_' src/$m.erl;
  done` → no output.
- `rebar3 compile` (zero warnings under `warnings_as_errors`), `xref`, `eunit`, CT,
  `proper`, `dialyzer`, scoped coverage ≥90% — all green; CI green on `task/0.6.0-m1`.

## Out of scope

Anything else in `erlmcp_client` (it's replaced by `erlmcp_client_session` in M3 —
do not refactor beyond the call site + dead records above). No other rows.

## Done when

The five Verify checks pass, M1-3 evidence is updated, gates and CI are green, and a
one-row closing note for M1-3 is submitted for CDC review.
