# CC Prompt — erlmcp 0.6.0, Milestone M1, Iteration 2 (close the CDC findings)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> This is an **in-milestone iteration on M1** — *not* a new milestone and *not* a
> deferral. CDC verified the closing report against the actual `task/0.6.0-m1`
> tree and found four rows that do not meet their criterion as written. You are
> closing them inside M1. **CDC re-runs the Verify commands and reads your diffs —
> not your summary — before M1 closes.**

## Context: what CDC found

The spine is sound — per-request worker isolation, cancellation-as-exit with no
late result, and the `gen_statem` lifecycle all verified correct. The closure is
blocked on four rows:

- **M1-2** was marked "done (partial scope)." That is not a terminal status, and
  the gap is real: **`erlmcp_json_rpc` has no batch handling at all**, and the
  error-code constants `-32602`/`-32603` are not defined (they appear only as
  magic-number literals). The criterion names batch envelopes and "graceful batch
  parsing"; the Verify requires "malformed batch degrades gracefully."
- **M1-3** was marked done, but the literal Verify `! grep -rn "^-record" include/`
  **fails** — 15 records remain in `include/erlmcp.hrl` — and `erlmcp_json_rpc`
  does `-export_type([json_rpc_message/0])` over a **record union**, i.e. a record
  in an exported spec, which the criterion forbids. (The new spine modules are
  genuinely record-free and consume JSON-RPC only via the tagged-tuple
  `decode_and_classify/1` — that part is good and must stay true.)
- **M1-16** and **M1-18** are **criterion-text defects in the ledger itself**, not
  implementation gaps (see Phase C). Treat them as amendments, not code.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M1-recore-ledger.md`** — rows M1-2, M1-3, M1-16, M1-18.
   Your definition of done for this iteration.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol; specifically the
   rules on terminal statuses (`done`/`deferred`/`no-op` only) and on raising an
   **amendment** instead of silently working around a wrong criterion.
3. **`priv/ai/erlang/SKILL.md`** — house style; **load first** and follow its own
   loading instructions.
4. **`src/erlmcp_json_rpc.erl`**, **`include/erlmcp.hrl`** — the code you're changing.

## Locked decisions (non-negotiable — unchanged)

- **JSON only via `erlmcp_codec`**; **`jesse`** at the session boundary; **OTP 25+**;
  **no macros for logic**; **no shared records across boundaries or in exported
  specs**; **validate at the edge, crash in the interior**.
- The new spine (`erlmcp_server_session`, `erlmcp_client_session`, `erlmcp_ctx`,
  `erlmcp_codec`, `erlmcp_model`, `erlmcp_capabilities`, `erlmcp_transport`,
  `erlmcp_transport_stdio`) **must remain record-free** and must keep consuming
  JSON-RPC only through the tagged-tuple `classified()` surface. Do not regress this.
- Build stays green under `warnings_as_errors`; the legacy modules still in
  `cover_excl_mods` (`erlmcp_client`, the sups, etc.) **must still compile**.

## Tasks

### Phase A — M1-2: batch + the full error-code set (real implementation)

Scope is the **`erlmcp_json_rpc` module** (encode / decode / classify). M1-2 does
**not** require session-level batch *execution* — do not gold-plate the session
with batch dispatch; that rides with the rest of the surface in M2. The bar is
that the codec module can round-trip and classify batches and degrade gracefully.

1. **Error-code constants.** Define the full set as named constants alongside the
   existing three in `include/erlmcp.hrl` (or, preferably, as part of the record
   relocation in Phase B, in the owning module): add `JSONRPC_INVALID_PARAMS`
   (`-32602`) and `JSONRPC_INTERNAL_ERROR` (`-32603`). Replace the magic-number
   literals (`-32602` in `erlmcp_server_session`, `-32603` in the worker-down path,
   and any in `erlmcp_json_rpc`) with the named constants. After this, the Verify's
   five-code set (`-32700/-32600/-32601/-32602/-32603`) is all named.

2. **Batch encode/decode/classify.** Per JSON-RPC 2.0:
   - A batch is a JSON **array** of one or more request/notification/response
     objects. Add `decode_and_classify/1` (or a sibling) handling of an array input
     so it returns a batch result — recommended shape `{ok, {batch, [Classified]}}`
     where each element is the existing `classified()` tuple, preserving per-member
     classification.
   - Encoding: provide a way to encode a list of messages as a batch array (mirror
     of the single-message encoders).
   - **Graceful degradation** (the named Verify): an **empty array** → a single
     Invalid Request (`-32600`) per the spec; a member that is not a valid object →
     that member classifies as an error result rather than crashing the whole
     decode; a top-level non-array, non-object → Parse/Invalid error as today. The
     decoder must never crash on malformed batch input — it returns errors.
   - Keep the single-message path behaviorally unchanged.

3. **Tests.** Extend `test/erlmcp_json_rpc_tests.erl`: encode/decode/classify of a
   mixed batch (requests + notifications), an all-notification batch, an empty-array
   batch, and a batch with one malformed member. Assert each of the five error
   codes is produced where the spec dictates. Extend the PropEr property (Phase C
   note applies) with a batch round-trip / malformed-batch-degrades property so the
   "graceful batch parsing" claim is property-checked, not just example-checked.

### Phase B — M1-3: empty `include/erlmcp.hrl` of records; drop the exported record type

Goal: `! grep -rn "^-record" include/` passes, **and** no in-scope module exports a
type that references a record. Mechanism is your call; here is the usage map CDC
already established so you don't have to re-derive it:

- **Dead — delete outright** (zero references anywhere in `src/`): `mcp_content`,
  `mcp_resource`, `mcp_resource_template`, `mcp_tool`, `mcp_prompt_argument`,
  `mcp_prompt`, `mcp_progress_token`, `mcp_progress_notification`.
- **Used only by `erlmcp_json_rpc`**: `json_rpc_request`, `mcp_error` → move to be
  **private records inside `erlmcp_json_rpc.erl`**.
- **Used by `erlmcp_json_rpc` *and* legacy `erlmcp_client`**: `json_rpc_response`,
  `json_rpc_notification`.
- **Used only by legacy `erlmcp_client`**: `mcp_capability`,
  `mcp_client_capabilities`.
- **Used by legacy `erlmcp_registry` *and* legacy `erlmcp_client`**:
  `mcp_server_capabilities`.

For the records the **legacy** modules need (`erlmcp_client`, `erlmcp_registry` —
both still in `cover_excl_mods`, both slated for replacement in M2/M3): relocate
them as **private records in the legacy module(s)** that use them, so nothing
remains in `include/`. Where a record is shared between two legacy modules, confirm
they do **not** pass that record across the module boundary at runtime (if they do,
that's a pre-existing legacy violation — note it, keep a private copy in each to
unblock, and flag it for the M2/M3 rewrite that deletes these modules). Do **not**
re-create a records header under `include/` — the Verify greps the whole directory.

Then, in `erlmcp_json_rpc`:

4. **Drop the record-union export.** Remove `-export_type([json_rpc_message/0])`
   and the `json_rpc_message/0` type (or redefine it privately if still needed
   internally). The **public** type surface must be the tagged-tuple `classified()`
   type — export that instead. No exported type may reference a record.
5. **`decode_message/1`.** It currently returns the record union as a public result.
   Either make it module-private, or change its public contract to return
   `classified()` tuples. The spine already uses `decode_and_classify/1`, so the
   public record-returning path has no in-scope caller — only the legacy client and
   the EUnit tests. Update `erlmcp_json_rpc_tests` accordingly.
6. **Re-verify the invariant didn't regress.** After the move, re-run CDC's spine
   check: `for m in erlmcp_server_session erlmcp_client_session erlmcp_ctx
   erlmcp_codec erlmcp_model erlmcp_capabilities erlmcp_transport
   erlmcp_transport_stdio; do grep -n 'erlmcp\.hrl\|#json_rpc_\|#mcp_' src/$m.erl;
   done` → expect **no output**.

### Phase C — M1-16 and M1-18: amend the criteria (ledger work, not code)

These two Verify commands were authored wrong; the honest close is an **amendment**
(raise it in the ledger per LEDGER_DISCIPLINE.md), not throwaway tests.

7. **M1-16.** The Verify's removal list names `erlmcp_app`, `erlmcp_sup`,
   `erlmcp_server_sup`, `erlmcp_session_sup`, `erlmcp_transport_sup`, and
   `erlmcp_registry` as modules that must leave `cover_excl_mods` this milestone —
   but M1 does **not** re-seat them (the supervision-tree rebuild is M2; the
   registry discovery-only rewrite with tests is M2; M1-13 only removed the routing
   helpers). Amend the M1-16 Verify to require removal + ≥90% of exactly the modules
   M1 actually re-seats — the spine list in "Locked decisions" above plus
   `erlmcp_json_rpc` — and to state explicitly that the sups + `erlmcp_registry`
   remain excluded with an M2 re-entry. Confirm by running the scoped coverage gate
   that every one of those spine modules is included and the aggregate holds ≥90%.
   Record the corrected Verify, the amendment rationale, and the evidence.
8. **M1-18.** The Verify names a property `prop_envelope_roundtrip` that does not
   exist; `test/prop_envelope.erl` provides five finer properties
   (`prop_request_roundtrip`, `prop_response_roundtrip`,
   `prop_error_response_roundtrip`, `prop_notification_roundtrip`,
   `prop_codec_roundtrip`). Amend the Verify text to name the actual properties
   (plus the new batch property from Phase A, task 3, and `prop_session_lifecycle`).
   This is a naming correction; the substance already exceeds the original.

## Working protocol

- **Branch:** continue on **`task/0.6.0-m1`** (the existing milestone branch); the
  PR into `release/0.6.x` stays open.
- Commit per row (or coherent group). In the closing commit, update
  `Status`/`Evidence` for **M1-2, M1-3, M1-16, M1-18** and record the M1-16/M1-18
  amendments.
- **No new "(partial scope)" pseudo-statuses.** Each touched row ends `done` with
  evidence, or — if something genuinely cannot be met in-milestone — `deferred` with
  a re-entry condition, raised explicitly. Given the direction here, the expectation
  is `done` on all four.
- Raise amendments; never silently work around. If Phase B uncovers a legacy
  record genuinely crossing a module boundary, **say so** rather than papering over it.
- Closing report: a per-row walk over **M1-2, M1-3, M1-16, M1-18** only (the other
  16 rows are already CDC-confirmed); no prose summary; name uncertainty.
- Iteration cap: this counts as M1 iteration 2 of 5. Subagents for lookup only.

## Out of scope for this iteration (do NOT build)

Session-level batch *execution* / response aggregation (M2 surface work). The full
`erlmcp_json_rpc` opaque-type rework beyond what Phase B requires. Any rewrite of
the supervisors or `erlmcp_registry` (M2). Touching the 16 already-confirmed rows.

## Done when

`! grep -rn "^-record" include/` passes; `erlmcp_json_rpc` exports no
record-referencing type and handles batch encode/decode/classify with graceful
malformed-batch degradation; the five error codes are named constants; the spine
remains record-free; EUnit + PropEr cover the new batch behavior; M1-16 and M1-18
carry corrected Verify text with raised amendments; `rebar3 compile` (zero
warnings), `xref`, `eunit`, CT, `proper`, `dialyzer`, and the scoped coverage gate
are green; CI is green on `task/0.6.0-m1`; and the four-row closing walk is
submitted for CDC review.
