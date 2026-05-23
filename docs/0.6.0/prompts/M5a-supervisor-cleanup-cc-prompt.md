# CC Prompt — erlmcp 0.6.0, supervisor cleanup (closes M4-12 + M5a-6 remainders)

> Imperative brief for **CC**. Small, surgical. On the current M5 branch
> (`task/0.6.0-m5`). **CDC re-runs the Verify commands and reads the diff — not the
> summary — before signing off M4 and M5a.**

## Why

The M5a-6 coverage pass (`8ebf079`) fixed the three session/facade modules
(`server_session` 93%, `client_session` 91%, `erlmcp` 97%) — proving those "deep
branch" lines were just untested, not unreachable. The **supervisors** were never
touched and are the last drag: `erlmcp_server_sup` 66%, `erlmcp_sup` 70%,
`erlmcp_transport_sup` 80%. Both the M4-12 and M5a-6 amendments file these under
"legacy wrappers / unreachable," which is **not true** — and one of them is a latent
bug, not uncovered code.

## Tasks

1. **Delete `erlmcp_server_sup:start_child/2`.** It is dead (zero callers in `src/` or
   `test/` — verify with `grep -rn "server_sup:start_child" src test`) **and broken**:
   it builds a full child-spec map and passes it to `supervisor:start_child/2` against
   a `simple_one_for_one` supervisor, which requires the extra-args *list* form. The
   live path, `erlmcp_sup:start_server/2`, already does it correctly
   (`supervisor:start_child(erlmcp_server_sup, [Opts])`). `start_child/2` is a broken
   duplicate of that path (violates "one way to do a thing") and a crash waiting to
   happen in an *exported* function. Remove it (and drop it from `-export`). This
   raises `server_sup` coverage by removing dead lines.

2. **Cover the live `erlmcp_sup` wrappers.** `start_server`/`start_transport` (and
   `stop_server`/`stop_transport`) are reachable via the facade and the test suites —
   their uncovered lines are the `{error, _}` / not-found / stop branches, not "legacy
   unreachable" code. Add targeted tests to bring `erlmcp_sup` to ≥90%.

3. **Cover `erlmcp_transport_sup` (80%)** the same way — test its reachable
   start_child / error branches to ≥90%, or, if any line is genuinely unreachable,
   name it line-by-line per the standing policy (don't blanket-amend).

4. **Rewrite the amendment text in both ledgers** to match reality:
   - **M4-12:** with `start_child/2` gone and the wrappers tested, `server_sup` /
     `erlmcp_sup` / `transport_sup` should be ≥90% — change the row to a clean `done`
     (no amendment) with the new per-module numbers. Remove the "substantive logic
     covered / below 90%" note.
   - **M5a-6:** the **only** remaining sub-90 module is `erlmcp_transport_stdio` (71%,
     the `io:get_line` reader loop — a genuine structural ceiling, ~33 named lines).
     Rewrite the amendment to name **stdio as the sole exception**, drop the "legacy
     supervisor wrappers (~40 lines)" and the "~120 deep-branch lines" language (both
     now disproven), and state the new honest aggregate.

5. **Re-run `rebar3 cover`** and report the new per-module table + aggregate. The
   aggregate should rise above 92%; the gate stays at the highest honest threshold
   (raise it if the new numbers support it, but don't pad).

## Acceptance / Verify

- `grep -n "start_child" src/erlmcp_server_sup.erl` → only the `init/1` template child
  spec remains (no exported `start_child/2`); `grep -rn "server_sup:start_child" src test`
  → no callers.
- `erlmcp_server_sup`, `erlmcp_sup`, `erlmcp_transport_sup` each ≥90% in `rebar3 cover`
  (or any sub-90 line named individually).
- M4-12 reads as a clean `done`; M5a-6's amendment names **only** stdio's io-loop.
- `rebar3 compile` (zero warnings), `xref`, `eunit`, CT, `proper`, `dialyzer` green;
  CI green.

## Out of scope

The stdio io-loop (accepted ceiling — leave it). No new features, no docs (that's
M5b), no other ledger rows. Do not touch the already-resolved session/facade modules.

## Done when

`erlmcp_server_sup:start_child/2` is gone; the three supervisors are ≥90% (or
named-line exceptions); the M4-12 and M5a-6 amendments are rewritten to name stdio as
the sole exception; coverage re-reported; gates and CI green; submitted for CDC
sign-off of M4 and M5a.
