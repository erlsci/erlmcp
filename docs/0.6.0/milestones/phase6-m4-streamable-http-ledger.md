# Phase 6, Milestone P6-M4: Streamable HTTP via Cowboy

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state — running each Verify command and reading diffs, not
> summaries. No milestone advances until the ledger is fully closed.

**Goal (Phase 6 §6, P6-M4):** the **second transport**, proving the spine
abstraction (server / session / responder / behaviour) genuinely generalizes.
Build a spec-conformant **Streamable HTTP** server (MCP 2025-11-25 protocol) on
**Cowboy**: a per-server listener, an endpoint handler for POST / GET / DELETE,
the `erlmcp_http_session_mgr` keyed by `Mcp-Session-Id`, an **SSE responder
adapter** with monotonic event ids + a bounded replay buffer for `Last-Event-ID`
resumability, and session GC. Lean on Cowboy maximally — it owns acceptor pool,
HTTP parsing, connection-process lifecycle, and SSE transport mechanics; we build
only the MCP semantics on top.

**The stdio-shaped stub `erlmcp_transport_streamable_http`** (single-session,
busy-poll accept, replies to most-recently-accepted socket — §1.3 of the original
design audit) is **deleted** in this milestone, replaced by the Cowboy-based
implementation.

**Exit:** concurrent multi-client correctness (responses correlate to the
*originating* connection, not the head of the list); SSE resume after a dropped
stream; session expiry and DELETE work; the deep paths (`slow_compute` task +
cancel; `explain` sampling) work over HTTP as they do over stdio; **both
transports green on one shared spine**.

**Locked decisions (carried + one amendment):**
- JSON via `jsx` behind `erlmcp_codec` only; `jesse` at the edge (not exercised
  here — that's P6-M5).
- Min OTP 25+. Dialyzer gated to OTP 27+ (`make dialyzer`); run on **27 and 28**.
- Coverage 90% per-module, scoped via `cover_excl_mods`; settle the M4 scope in
  the first commit (P6M4-19).
- Validate at the edge, crash in the interior; opaque types + accessors; no
  shared records; one way to do a thing.
- **Never loosen a check to make it pass** (`CLAUDE.md`): no suppressions, no
  widened specs, no skipped tests — escalate instead.
- **Amendment (recorded at the top of this ledger as P6M4-1):** **`cowboy`**
  (and its transitive dep `ranch`) added to the accepted dependency set
  (previously `jsx` + `jesse`). Justification: a correct Streamable HTTP server
  is a hard 0.6.0 blocker, and hand-rolling HTTP/1.1+2/SSE is precisely the kind
  of work the original stub failed at (§1.3) — Cowboy is the BEAM-standard
  acceptor-pool + HTTP server and the right tool for the job.

**Branch:** `task/0.6.0-p6m4`, cut from `release/0.6.x` **after P6-M3 merges**.
PR back into `release/0.6.x`. All Verify commands run from the repo root. All
rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| P6M4-1 | **Dependency amendment:** `cowboy` (and `ranch`) are added to `rebar.config` deps with pinned versions; their addition is recorded in this ledger as an amendment to the locked-deps decision. | `grep -nE "cowboy" rebar.config`; `rebar3 deps` lists `cowboy` + `ranch` at the chosen versions. | serious | Phase 6 §2 mandate; Cowboy boundary §5 | open | | Pin to a recent stable cowboy release (2.x). Document the version choice. |
| P6M4-2 | **`erlmcp_reply` gains the HTTP and SSE responder kinds.** `{http, ConnPid, ReqRef}` writes the JSON-RPC reply onto the originating POST connection; `{sse, StreamPid}` formats an `text/event-stream` event (with a monotonic event id) and writes it to the standing SSE stream. The session core does not change. | `grep -nE "\\{http,\\|\\{sse," src/erlmcp_reply.erl`; EUnit `erlmcp_reply_tests`: device / http / sse kinds each deliver under a stub target; unit test for SSE event formatting. | serious | Phase 6 §3.3 (the single per-transport branch point) | open | | The whole point of the M1 responder design lands here: the session core is unchanged; only the responder grows two new kinds. |
| P6M4-3 | A **per-server Cowboy listener** is started (via `cowboy:start_clear` or `cowboy:start_tls`) under the per-server subtree, bound to a configurable port, with a single MCP endpoint route (default `/mcp`) dispatching to the endpoint handler. | CT: starting a server with `transport => http, port => 0` (ephemeral) yields a listening port; tearing down the server stops the listener cleanly. | serious | Phase 6 §3.5; Cowboy boundary §5 | open | | One listener per `erlmcp_server`. Multi-tenant (one listener routing to many servers) is out of scope. |
| P6M4-4 | The endpoint handler accepts **`POST`** with a JSON-RPC message or batch in the body; reads `Mcp-Session-Id` from the request headers (if present); routes the message to the correct session via the session manager. | CT: a `POST` of a well-formed `initialize` returns a `200`; a `POST` with `Mcp-Session-Id` of a known session is dispatched to that session. | serious | MCP 2025-11-25 Streamable HTTP transport | open | | Content-type for the request: `application/json`. Reject non-JSON with `415`. |
| P6M4-5 | **POST response: `application/json` or `text/event-stream`.** For a single one-shot response, the handler replies with `application/json` and the JSON-RPC response body. For requests that fan out to multiple server→client messages (e.g. sampling, progress), the handler **upgrades the response to SSE** for that POST, streams the events, and closes when the originating request's response is delivered. | CT: a simple `tools/call` returns `Content-Type: application/json`; a `tools/call` that issues `sampling/createMessage` back to the client (e.g. `explain`) returns `Content-Type: text/event-stream` and the SSE stream carries both the sampling request *and* the eventual tool result. | serious | MCP 2025-11-25 Streamable HTTP transport | open | | The decision (`application/json` vs SSE upgrade) is the responder's: if the session emits a server→client request before the tool result, the responder switches to SSE; otherwise plain JSON. |
| P6M4-6 | **`GET`** on the endpoint opens a standing SSE stream for **unsolicited** server→client traffic (notifications, server-initiated requests outside the POST/response cycle). | CT: `GET` with `Accept: text/event-stream` returns `200` + `Content-Type: text/event-stream`; a server-emitted notification is received on the stream. | serious | MCP 2025-11-25 Streamable HTTP transport | open | | The session's **push channel** (responder for unsolicited traffic) is bound to this stream while it's open. |
| P6M4-7 | **`DELETE`** on the endpoint with a valid `Mcp-Session-Id` terminates that session. | CT: a `DELETE` for a known session returns `200`; subsequent requests with that `Mcp-Session-Id` return `404` (or the spec-specified status). | serious | MCP 2025-11-25 Streamable HTTP transport | open | | The session's supervisor terminates the session pid; the session manager evicts the id. |
| P6M4-8 | **`erlmcp_http_session_mgr`** mints an `Mcp-Session-Id` on `initialize`, looks it up on subsequent requests, and evicts on DELETE or idle expiry. Opaque, server-generated id (UUID-like; not user-supplied). | EUnit: mint returns a binary; lookup returns the session pid for a known id and `{error, not_found}` for an unknown one; eviction returns `ok` and a subsequent lookup is `not_found`. | serious | Phase 6 §5 (HTTP specifics) | open | | Keyed registry distinct from `erlmcp_registry` (which stays a pure name directory). |
| P6M4-9 | **SSE adapter:** monotonic per-stream event ids; a **bounded replay buffer** retains the last *N* events (configurable, default reasonable e.g. 100); a `Last-Event-ID` request header on stream open replays events after that id. | CT: open SSE → send N+5 events → close → reopen with `Last-Event-ID: <Nth>` → receive the 5 missed events; opening with a stale id older than the buffer yields the buffered tail with a documented gap-handling behaviour. | serious | MCP Streamable HTTP resumability | open | | This is the spec's resumability guarantee. Replay buffer size is a configurable per-server limit. |
| P6M4-10 | **Session lifetime is decoupled from any single connection.** A dropped SSE stream does **not** terminate the session — only DELETE or idle GC does. | CT: open SSE → drop the stream → confirm session is still alive (POST still routes to it); reconnect SSE with `Last-Event-ID` and confirm replay. | serious | Phase 6 §5 (handoff §5 best practice) | open | | Monitors, not links, across the connection↔session boundary — naturally satisfied because Cowboy owns handler processes that talk to sessions by message; the session manager monitors *sessions* (not the other way) to prune the map. |
| P6M4-11 | **Session GC via idle timeout.** Each session has a configurable idle timeout (default reasonable, e.g. 5 minutes); after the timeout with no activity, the session is terminated and evicted from the manager. | CT: short timeout (e.g. 500ms) is wired through config; after that with no activity the session is gone (lookup → `not_found`). | correctness | Phase 6 §5 | open | | Configurable per-server. "Activity" = any inbound request *or* any outbound emit. |
| P6M4-12 | **Concurrent multi-client correctness:** N concurrent `POST`s from N distinct sessions get responses **correlated to the originating connection**, not the most-recently-accepted (the original stub's bug, §1.3). | CT/PropEr: spawn N (≥10) parallel clients, each starts a session and fires `tools/call`; each receives only its own response on its own connection. | serious | Phase 6 §1.3 (the stub's exact bug); MCP correctness | open | | The single test that proves the per-request reply-target design from P6-M1 actually works under load on the HTTP side. |
| P6M4-13 | **In-session concurrency correctness:** within one session, M concurrent `POST`s correlate by JSON-RPC `id` back to the right POST connection (response id matches request id). | CT: open one session; fire M (≥5) `POST`s in parallel with distinct ids; each response lands on its own request's connection. | correctness | MCP correctness | open | | Guards against accidental id confusion within a single client's pipeline. |
| P6M4-14 | **E2E over HTTP:** `initialize → ping → tools/list → tools/call → cancel` (the M2 scenario, mirrored). | CT `erlmcp_http_e2e_SUITE`: scenario passes over the real Cowboy transport (a real HTTP client driving the listener). | serious | M2 parity | open | | Mirror of P6M2-8. Same scenario, different transport. |
| P6M4-15 | **Race conformance over HTTP:** register N tools + M resources + K prompts via config; `tools/list`/`resources/list`/`prompts/list` each return all of them. | CT: counts equal N/M/K for all three list endpoints. | serious | M2 parity (P6M2-6); Phase 6 §1.4 | open | | The race-fix is structural in the spine; this test confirms HTTP doesn't reintroduce it. |
| P6M4-16 | **Deep paths over HTTP** — the BEAM differentiators and the full-duplex contract: (a) `slow_compute` emits `notifications/progress` over the SSE upgrade and is **cancellable** mid-flight; (b) `explain` issues `sampling/createMessage` back to the client over the SSE channel and consumes the reply. | CT `erlmcp_http_deep_protocol_SUITE`: task progress + cancel; sampling round-trip over SSE. | serious | M2 parity (P6M2-18); native-strength differentiators | open | | The proof that HTTP genuinely supports the same bidirectional contract stdio does. |
| P6M4-17 | **Both transports green on one shared spine.** The same `erlmcp_server`, `erlmcp_server_session`, `erlmcp_reply` (with the new kinds), and redefined `erlmcp_transport` behaviour drive both stdio and HTTP. All M2 stdio CTs **still pass unchanged**. | `make check` exits 0 incl. all stdio + HTTP suites; the stdio per-server subtree still functions as in M2. | serious | Phase 6 §3 — the unification mandate | open | | This is what makes the whole architectural bet pay off. |
| P6M4-18 | **The stub is replaced.** `src/erlmcp_transport_streamable_http.erl` is **deleted**; its `cover_excl_mods` entry is removed (it no longer exists). The Cowboy-based implementation takes its place. | `! ls src/erlmcp_transport_streamable_http.erl 2>/dev/null`; `cover_excl_mods` no longer lists `erlmcp_transport_streamable_http`. | serious | Phase 6 §7; M1/M2 carry-forward | open | | The stub was always slated for deletion here; do it cleanly. |
| P6M4-19 | **Coverage scoping (pre-specified, M1/M2 lesson):** the new HTTP modules (e.g. `erlmcp_transport_http_server`, `erlmcp_http_session_mgr`, the SSE adapter) are **included** at ≥90% per-module; `cover_excl_mods` retains only orthogonal/out-of-scope modules (client transports `erlmcp_transport_tcp`/`erlmcp_transport_http`, example modules → P6-M6) with re-entry noted. | `rebar3 as test cover -v --min_coverage=90` exits 0; per-module ≥90% on the new HTTP modules; every `cover_excl_mods` entry has a re-entry note in this ledger. | serious | Locked decision (coverage); M1/M2 lesson | open | | Settle the exclusion list in the first commit, not under pressure later. |
| P6M4-20 | **Dialyzer clean on OTP 27 AND 28** under the strict set, **no suppressions**, no widened specs. (Closes the same way as P6M3-10 — together with P6M4-21 on the CI matrix.) | `make dialyzer` clean on 27 and 28; `! grep -rn "nowarn\\|-dialyzer(" src` (no new suppressions). | serious | DoD; `CLAUDE.md` never-loosen rule | open | | Cowboy + ranch dialyzer specs should pass cleanly. If a cowboy callback signature trips strict mode, escalate — don't suppress. |
| P6M4-21 | **CI green** on `task/0.6.0-p6m4` across the OTP 25–28 matrix. | CI workflow (compile + xref + examples + eunit + CT + proper + dialyzer[27/28] + cover) passes on the branch. | serious | DoD | open | | The independent reproducer; also confirms the 27 leg of P6M4-20. |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
milestone. `correctness` = a guarantee P6-M4 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to P6-M5+

_(Filled in at close — e.g. example servers exposing HTTP transports as a
configuration option (P6-M6); a "deploying a Streamable HTTP server" section in
the howto (P6-M7); strict payload validation via jesse on both transports
(P6-M5). Note any module still in `cover_excl_mods` with its re-entry milestone.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 21. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
