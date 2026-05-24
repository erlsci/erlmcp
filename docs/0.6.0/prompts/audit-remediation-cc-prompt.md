# CC Prompt — erlmcp 0.6.0 pre-release audit remediation

> Imperative brief. Closes the **fix-now** findings from the pre-release audit
> (`workbench/2026.05.24-audit-results-erlang.md`) so 0.6.0 is clean to tag. Three small
> code fixes + bookkeeping. CDC reviewed the audit and concurs with these dispositions.
> **CDC re-verifies the diffs before the tag.**

## Why

CDC spot-checked the audit; the findings are real. Three are cheap and worth fixing
**before tagging 0.6.0** rather than deferring; the rest (the remaining Mediums + 10
Lows) go to the M7 polish backlog. No Blockers — this is the last gate before release.

## Read first

- `workbench/2026.05.24-audit-results-erlang.md` — findings F-01, F-04, F-09 (+ the
  deferred ones), with cited rules.
- `src/erlmcp_server_session.erl` `handle_batch/2` + `dispatch_batch_request/4` (≈ 281–318);
  `handle_outbound_response/3` (the out_pending correlation, M3b).
- `src/erlmcp_sup.erl` `init/1`; `src/erlmcp_session_sup.erl`.

## Tasks (fix-now)

### 1. F-04 — delete the dead `erlmcp_session_sup`

It has **zero callers**; `erlmcp_sup:start_server/2` starts sessions only via
`erlmcp_server_sup`. It's a redundant `simple_one_for_one` for the same child module
that bypasses registry tracking if mistakenly used (and it was "100% covered" only
because a test instantiated it standalone — covered ≠ used).

- Delete `src/erlmcp_session_sup.erl`.
- Remove its child spec from `erlmcp_sup:init/1`.
- Remove/adjust any test that started it standalone (e.g. in `erlmcp_supervision_SUITE`).
- **Verify:** `grep -rn erlmcp_session_sup src test` → no matches; `cover_excl_mods`
  stays `[]`; CI green.

### 2. F-09 — stop silently dropping batched responses; close the `out_pending` leak

In `handle_batch/2`, `{response, _, _}` and `{error_response, _, _}` items currently
`filtermap` to `false` — silently dropped. If a batch carries a reply to a
server-initiated request (sampling/roots/elicitation), `handle_outbound_response/3`
never fires, so the `out_pending` entry **leaks** (the `request_peer` worker only
unblocks via its 30s timeout, and the map entry is never cleaned).

- Refactor `handle_batch/2` so it **threads `Data`** (a `foldl`, not a `filtermap`):
  request/parse_error items still collect a reply for the batch array; **`{response, Id,
  Result}` and `{error_response, Id, Error}` items route through the
  `handle_outbound_response/3` effect** (reply the waiting worker + remove the
  `out_pending` entry), contributing no batch reply.
- The `_ ->` catch-all must **not silently drop** — at minimum log it; better, treat it
  as an invalid-request error reply. (AP: wildcard catch-all suppressing exhaustiveness.)
- **Verify:** a CT case where a batch containing a `{response, Id, _}` for a live
  `out_pending` entry cleans that entry (no leak) and unblocks/answers the worker; the
  existing batch CT (`batch_mixed`/`batch_all_notifications`/`batch_malformed_member`)
  still passes.
- *If full routing proves larger than a small fix, stop and raise it* — but the leak
  fix (route responses to `handle_outbound_response`) is the bar; do not ship the silent
  drop.

### 3. F-01 — document the batch functional limitation

`dispatch_batch_request/4` handles only `ping` + `tools/list`; **every other method
(including `tools/call`) returns `method_not_found`**, and dispatch is synchronous in
the FSM. That's safe *because* only intrinsic fast methods run — but the structure
invites a future maintainer to add a handler-backed method and block the FSM.

- Add a doc comment on `handle_batch/2` / `dispatch_batch_request/4` stating: batch
  supports only intrinsic fast methods (`ping`, `tools/list`); all others →
  `method_not_found`; dispatch is intentionally synchronous and **must not** be extended
  to handler-backed methods without per-member worker dispatch (else the FSM blocks).

## Bookkeeping

### 4. Correct the M6b-3 evidence (audit-driven clarification, not a reopen)

In `docs/0.6.0/milestones/M6b-meta-icons-batch-finish-ledger.md`, M6b-3's evidence
overstates "session-level batch execution." Append a clarifying note: batch dispatches
`ping`/`tools/list` inline (not via workers), other methods → `method_not_found`, and
(post-fix) batched responses route to `out_pending`. M6b-3 stays `done`; this just makes
the evidence match the code.

### 5. Close the audit dispositions + feed the backlog

- In `workbench/2026.05.24-audit-results-erlang.md`, mark F-01/F-04/F-09 **resolved**
  (with the fixing commit), and mark the remaining Mediums + 10 Lows **deferred → M7**.
- Append the deferred items to `docs/0.6.0/planning/M7-post-0.6-backlog.md` (Cluster B,
  with their F-IDs + file:line) so they're tracked, not lost.

## Working protocol

- **Branch:** `task/0.6.0-audit-remediation`, off `release/0.6.x`; PR into `release/0.6.x`.
- Commit the three fixes (coherent group) + the bookkeeping; per-row evidence for any
  ledger touched.
- Raise an amendment if any "fix-now" turns out non-trivial (esp. F-09) rather than
  half-doing it.
- `rebar3 compile` (zero warnings), `xref`, `eunit`, CT, `proper`, `dialyzer`, cover
  (`cover_excl_mods` stays `[]`, gate holds) all green.

## Out of scope

The deferred Mediums (perf: `length/1` scans, `++`-in-`foldl`) and the 10 Lows — those
are M7. No `server_session` god-module extraction (M7). No new features. Only F-01,
F-04, F-09 + the bookkeeping.

## Done when

`erlmcp_session_sup` is gone; batched responses route to `out_pending` (no silent drop,
no leak) and the catch-all doesn't silently swallow; the batch limitation is documented;
M6b-3 evidence matches the code; the audit dispositions are closed and the deferred items
are in the M7 backlog; gates + CI green. Submitted for CDC sign-off — the last gate
before tagging 0.6.0.
