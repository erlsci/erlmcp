# CC Prompt — erlmcp 0.6.0, Milestone M1 (The re-core)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before M1 closes. This is the load-bearing milestone; build the spine
> carefully and let the four-state session + per-request worker model do the work.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M1 only**: the foundational
re-core. The target is a working **stdio** session that can `initialize`, `ping`,
negotiate version, and `cancel` — end to end — and nothing more. No feature
surface (tools/resources/prompts/logging/completion/pagination) — that's M2.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M1-recore-ledger.md`** — the M1 ledger (rows M1-1…M1-20).
   Your definition of done; you'll report a disposition for every row.
2. **`LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`docs/0.6.0/planning/phase2-idiomatic-erlmcp.md`** — §2 (model/codec), §3
   (concurrency & lifecycle — the heart of this milestone), §4 (registry), §5
   (error handling: validate-at-edge), §6 (transport behaviour), §8 (capabilities/
   version negotiation).
4. **`docs/0.6.0/planning/phase3-gap-analysis.md`** — the C and A gaps M1 closes.
5. **`docs/0.6.0/milestones/M0-decide-scaffold-clear-ledger.md`** — the "Carry-forward
   to M1" section: the `_new`-logic re-seat, the server collapse (M0-2), the codec
   boundary, and the `cover_excl_mods` shrink.

**House style — load this first:** read `./priv/ai/erlang/SKILL.md` and follow its
own loading instructions (it indexes `priv/ai/erlang/guides/`). This is the
authoritative erlmcp Erlang skill and the operative coding reference for this
milestone; it supersedes the interim "Inaka + OTP texts" bar (the
`phase0-erlang-rubric` remains the underlying rationale).

## Locked decisions (non-negotiable)

- **JSON = `jsx` only inside `erlmcp_codec`.** No `jsx:` calls anywhere else (M1-1).
- **Schema validator = `jesse`.**
- **Minimum OTP = 25+.** No features newer than OTP 25.
- **Coverage = 90% scoped** to implemented modules; this milestone *shrinks* the
  exclusion list (M1-16) as modules are re-seated.
- **Validate at the edge, crash in the interior** (Phase 2 §5): no defensive `try`
  around business logic inside workers; translate at the session↔worker boundary.
- **No shared records** across module boundaries or in exported specs (Phase 2 §2).
- **One way to do a thing** — no `_new` modules.

## Tasks (each maps to ledger rows; suggested build order is bottom-up)

**Phase A — wire & model (pure units, easy to test first).**
1. **[M1-1]** `erlmcp_codec`: the only `jsx` caller; encode/decode + round-trip tests.
2. **[M1-2]** `erlmcp_json_rpc`: 2.0 envelope encode/decode/classify (request/
   response/notification/batch), full error-code set, graceful batch parsing.
3. **[M1-3]** `erlmcp_model`: opaque types + constructors/accessors; no shared records.
4. **[M1-4]** `erlmcp_capabilities`: capability map derived from registration +
   highest-mutual version negotiation over a declared supported-version set.

**Phase B — transport & registry.**
5. **[M1-11]** `erlmcp_transport` behaviour with the §6 callbacks (`init/2`,
   `send/2`, `close/1`, optional `get_info/1`, `handle_transport_call/2`).
6. **[M1-12]** `erlmcp_transport_stdio` as a `gen_server` implementing it,
   delivering inbound **directly to the bound session**, deadlock fixed, iolist
   framing. Mirror the pid-based `erlmcp_transport_http` pattern (commit 57e2f50).
7. **[M1-13]** `erlmcp_registry`: discovery/binding only — strip per-message routing.

**Phase C — the spine (Phase 2 §3, the headline divergence).**
8. **[M1-5]** `erlmcp_server_session` as a `gen_statem`: `uninitialized →
   initializing → operational → shutting_down`; gate method legality by state +
   negotiated capabilities.
9. **[M1-7]** Per-request worker model: session spawns + monitors one process per
   in-flight request; crash → `-32603` + session survives; no head-of-line block.
   Exercise it via a **minimal/test request path** (e.g. a trivial echo/crash test
   handler) — the full `tools/call` surface is M2, do not build it here.
10. **[M1-8]** `erlmcp_ctx`: progress token / cancellation / `_meta` / peer handle;
    `report_progress/3` → `notifications/progress`.
11. **[M1-9]** Cancellation = kill the worker on `notifications/cancelled`; no token
    map; no late result.
12. **[M1-10]** `ping` + request-id correlation table (concurrent requests correlate).
13. **[M1-6]** `erlmcp_client_session` `gen_statem`: enough to drive
    `initialize`, `ping`, and issue cancellation. **Full client API is M3** — stop
    at what the e2e scenario needs.

**Phase D — carry-forwards & cleanup.**
14. **[M1-14]** Re-seat the M0-1 `_new` logic (registry-aware routing → session;
    `TransportId` init → `init/2`; async-cast send → `send/2`), or drop with
    rationale — write the disposition for each of the three.
15. **[M1-15]** Delete `erlmcp_server.erl` and `erlmcp_stdio_server.erl` once
    `erlmcp_server_session` subsumes them (closes deferred **M0-2**). Update any
    references (e.g. `erlmcp_server_sup`, the facade) accordingly.
16. **[M1-16]** Remove the M1-tagged modules from `cover_excl_mods`
    (`erlmcp_app`, `erlmcp_sup`, `erlmcp_server_sup`, `erlmcp_session_sup`,
    `erlmcp_transport_sup`, `erlmcp_server`, `erlmcp_json_rpc`, `erlmcp_registry`,
    `erlmcp_stdio`, `erlmcp_stdio_server`) and bring each to ≥90% coverage.

**Phase E — acceptance & gates.**
17. **[M1-17]** CT `erlmcp_e2e_SUITE`: stdio client+server, same VM,
    `initialize → ping → cancel`.
18. **[M1-18]** PropEr: `prop_envelope_roundtrip` + `prop_session_lifecycle`.
19. **[M1-19]** `rebar3 dialyzer` clean.
20. **[M1-20]** CI green on `task/0.6.0-m1`.

## Working protocol

- **Branch:** `task/0.6.0-m1`, cut from `release/0.6.x`; PR into `release/0.6.x`.
  (CI fires on `task/**` and `release/**`; a bare `0.6.0-m1` does not.)
- **Commit per ledger row** (or coherent group); in the same commit update that
  row's `Status`/`Evidence` (commit SHA + Verify output).
- **Raise, don't route around.** If a criterion is wrong, impossible, or needs a
  later milestone, raise an amendment (ledger Notes + flag to CDC); never silently
  work around. The coverage scoping (M1-16) especially: if a re-seated module can't
  reach 90% honestly, raise it — do not pad tests or re-exclude it without a noted
  rationale and re-entry.
- **Closing report:** a per-row walk over all 20 rows — `done`+evidence,
  `deferred`+reason+re-entry, or `no-op`+rationale. No prose summary. Name uncertainty.
- **Iteration cap: 5.**
- **Subagents for lookup only**, never implementation or judgment.

## Out of scope for M1 (do NOT build)

- `tools/call` feature surface: schema validation wiring, content types,
  annotations, `list_changed` — **M2**.
- Resources, prompts, logging, completion, pagination, progress-beyond-ctx — **M2**.
- Full client API (list/read/call/get, subscriptions) — **M3**.
- TCP / HTTP / streamable-HTTP transports — **M4** (stdio only here).
- Tasks (`tasks/*`) — **M6**.

Build only the per-request worker *mechanism* and the minimal request path needed
to prove `initialize → ping → cancel` and crash isolation. Everything else waits.

## Done when

All 20 ledger rows have a final status; CT e2e + PropEr + Dialyzer + CI all green;
the closed ledger is submitted for CDC review.
