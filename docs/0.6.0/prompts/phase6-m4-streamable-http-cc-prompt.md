# CC Prompt — erlmcp 0.6.0, Phase 6 / Milestone P6-M4 (Streamable HTTP via Cowboy)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before P6-M4 closes. This is the **headline architectural milestone
> of Phase 6**: it proves the unified-transport bet by adding a second transport
> that shares the spine with stdio. Get the seam right and stdio + HTTP run on
> one engine; get it wrong and they diverge into two parallel servers.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **P6-M4 only**: a
spec-conformant **Streamable HTTP** server (MCP 2025-11-25 protocol) on Cowboy.
You add the `{http, ConnPid, ReqRef}` and `{sse, StreamPid}` responder kinds, a
per-server Cowboy listener with the MCP endpoint handler, the
`erlmcp_http_session_mgr` keyed by `Mcp-Session-Id`, the SSE responder adapter
with monotonic event ids + a bounded replay buffer + `Last-Event-ID` resumability,
and session GC. You **delete** the old `erlmcp_transport_streamable_http` stub.
You do **not** touch the session core, the existing stdio transport, or the
`erlmcp_server` catalog — they should already be sufficient.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/phase6-m4-streamable-http-ledger.md`** — the P6-M4
   ledger (rows P6M4-1…P6M4-21). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`docs/0.6.0/planning/phase6-unified-transport-architecture.md`** —
   especially §3.3 (the responder seam — the single per-transport branch point),
   §3.4 (the redefined `erlmcp_transport` behaviour), §3.5 (per-transport tiers
   — stdio's degenerate-case vs HTTP's full subtree), and **§5 (the Cowboy
   boundary — what Cowboy owns vs what we build)**. Re-read §5 carefully: it is
   the contract for this milestone.
4. **`docs/0.6.0/planning/schema.ts`** — the MCP protocol schema (2025-11-25).
   The Streamable HTTP transport section is the spec for POST/GET/DELETE,
   `Mcp-Session-Id`, and `Last-Event-ID` semantics. **Defer to the spec on any
   wire-format question.**
5. **`CLAUDE.md`** — especially *Never loosen a check to make it pass* and the
   coverage rule. **House style:** `priv/ai/erlang/SKILL.md` first
   (`11-anti-patterns.md`, then `06-processes-and-concurrency.md`,
   `07-otp-behaviours.md`, `08-supervision-and-applications.md`).

## Locked decisions (non-negotiable)

- JSON via `jsx` inside `erlmcp_codec` only; `jesse` at the edge **not** exercised
  here (that's P6-M5; do not start it).
- Min OTP 25+. Dialyzer is gated to OTP 27+ — run `make dialyzer` on **27 and 28**.
- Coverage 90% per-module, scoped via `cover_excl_mods`; **settle the M4 scope in
  your first commit** (P6M4-19).
- Validate at the edge, crash in the interior. Opaque types + accessors. No
  shared records across boundaries.
- **Never loosen a check to reach green** — no suppressions, no widened specs to
  silence dialyzer, no skipped tests. Escalate, don't loosen.
- **New dependency amendment (P6M4-1):** `cowboy` (and `ranch`) are added to
  `rebar.config`. Pin a recent stable cowboy 2.x; document the choice. This is
  the only deps change.

## Cowboy boundary — what Cowboy does vs what you build

**Cowboy owns** (do not re-implement): TCP acceptor pool via `ranch`,
HTTP/1.1+2 parsing, request/body reading, response writing,
connection-process lifecycle, the SSE transport mechanics (streaming
handlers / loop handlers). A Cowboy handler process *is* the
connection/request process; Cowboy owns its lifecycle.

**You build** (the MCP layer only):

- An **endpoint handler module** (a Cowboy handler — likely a `cowboy_loop` /
  streaming handler) that interprets `POST` / `GET` / `DELETE` per the MCP
  Streamable HTTP spec.
- **`erlmcp_http_session_mgr`** — keyed registry `Mcp-Session-Id → session pid`.
  Mint on `initialize`, look up on subsequent requests, evict on `DELETE` or
  idle GC. Distinct from `erlmcp_registry` (which stays a pure name directory).
- **SSE responder adapter** in `erlmcp_reply` — when emitting via `{sse, StreamPid}`,
  format an `id:` + `data:` event with a monotonic per-stream event id and append
  to the stream's **bounded replay buffer**. On a fresh GET with `Last-Event-ID`,
  replay events after that id from the buffer.
- **Session GC** — configurable idle timeout per server; session terminates and
  is evicted after no activity for that interval.
- **Per-server listener wiring** — one `cowboy:start_clear` listener per
  `erlmcp_server`, bound to a configurable port, dispatching to your handler
  module on a single MCP endpoint path (default `/mcp`).

**Critical seam (do not break):** the **session core does not change**. The only
new code in `erlmcp_reply` is two new kinds (`{http,_,_}` and `{sse,_}`) and
their `send/2` implementations. Sessions emit via the responder as they always
have. If you find yourself touching `erlmcp_server_session`'s state record or
its dispatch, **stop and escalate** — you're crossing the seam.

## Tasks (each maps to ledger rows; suggested build order is bottom-up)

**Phase A — deps + responder seam.**
1. **[P6M4-1]** Add `cowboy` (and transitive `ranch`) to `rebar.config`; pin a
   recent stable cowboy 2.x; record the version in the ledger note.
2. **[P6M4-2]** Extend `erlmcp_reply` with the `{http, ConnPid, ReqRef}` and
   `{sse, StreamPid}` kinds. `send/2` for `{http,_,_}` sends a message the
   endpoint handler picks up to write the `application/json` response and close;
   `send/2` for `{sse,_}` formats an SSE event and writes it. Unit-test both
   under stub targets. **No session-core changes.**

**Phase B — endpoint handler + session manager.**
3. **[P6M4-3]** A per-server Cowboy listener (one MCP endpoint route, configurable
   port). Started under the per-server subtree from M2 (extend the subtree sup).
4. **[P6M4-8]** `erlmcp_http_session_mgr` — keyed registry, mint/lookup/evict
   API. Opaque, server-generated id (UUID-like; don't accept user-supplied ids).
5. **[P6M4-4, P6M4-7]** Endpoint handler for `POST` (with `Mcp-Session-Id`) and
   `DELETE` (terminates the session). `415` on non-JSON content-type;
   spec-conformant statuses for unknown / expired sessions.

**Phase C — SSE + resumability.**
6. **[P6M4-6]** Endpoint handler for `GET` with `Accept: text/event-stream` —
   opens a standing SSE stream; the session's push channel responder becomes
   `{sse, StreamPid}` while the stream is open.
7. **[P6M4-5]** POST response decision: `application/json` for simple one-shot
   responses; **upgrade to SSE** if the session emits server→client traffic
   before the tool result (e.g. sampling, progress). Stream events on the POST's
   connection until the originating request's response is delivered, then close.
8. **[P6M4-9]** SSE adapter: monotonic event ids per stream; **bounded replay
   buffer** (configurable size, e.g. default 100); on stream open with
   `Last-Event-ID`, replay events after that id. Document the gap-handling for
   ids older than the buffer.

**Phase D — lifetime + GC.**
9. **[P6M4-10]** Verify (with a test) that a dropped SSE stream does **not**
   terminate the session — only DELETE or idle GC does. Monitors, not links,
   across the connection↔session boundary.
10. **[P6M4-11]** Configurable session idle timeout; GC terminates + evicts.
    Default a reasonable value (e.g. 5 minutes).

**Phase E — conformance + parity.**
11. **[P6M4-12, P6M4-13]** Concurrent client correctness CTs: N concurrent
    distinct sessions; M concurrent in-session POSTs. Each response lands on its
    own connection / matches its own id. **This is the test that proves the
    per-request reply-target design from M1 actually works under load.**
12. **[P6M4-14]** E2E over HTTP: `initialize → ping → tools/list → tools/call →
    cancel` (mirror of P6M2-8 over the new transport).
13. **[P6M4-15]** Race conformance over HTTP: register N tools + M resources + K
    prompts via config; assert all list endpoints return all items.
14. **[P6M4-16]** Deep paths over HTTP: `slow_compute` progress + cancel (over
    the SSE upgrade); `explain` sampling (`sampling/createMessage` back to the
    client over the SSE channel).
15. **[P6M4-17]** **Both transports green on one shared spine** — all M2 stdio
    CTs **still pass unchanged** alongside the new HTTP CTs; `make check` green.

**Phase F — cleanup + gates.**
16. **[P6M4-18]** **Delete** `src/erlmcp_transport_streamable_http.erl` (the
    stub). Remove its `cover_excl_mods` entry.
17. **[P6M4-19, P6M4-20, P6M4-21]** Coverage scoping pre-specified at the first
    commit, ≥90% per-module on the new HTTP modules; `make dialyzer` clean on 27
    **and** 28 with zero suppressions; CI green.

## Working protocol

- **Branch:** `task/0.6.0-p6m4`, cut from `release/0.6.x` **after P6-M3 merges**;
  PR back into `release/0.6.x`.
- **Commit per coherent group** (deps + responder kinds → listener + manager →
  handler → SSE/resumability → GC → conformance/parity → cleanup → gates); update
  Status/Evidence per row in the closing commit.
- **Raise, don't route around.** Wrong/impossible criterion → amendment with
  re-entry. Dialyzer warning that looks wrong → escalate `file:line`; never loosen.
  Cowboy callback signature trips strict mode → escalate, don't suppress.
- **Closing report:** **per-row walk over all 21 rows.** No prose summary. Name
  uncertainty. Recurring lesson: enumerate the *actual* row count from the ledger
  file — don't stop at 16 if it has 21.
- **Iteration cap: 5.**
- **Subagents for lookup only.**

## Out of scope for P6-M4 (do NOT build)

- **Example servers exposing HTTP** — example app+release work is **P6-M6**.
  Test fixtures driving HTTP from CTs are fine; rewriting calculator/weather as
  HTTP-capable apps is not.
- **jesse payload validation** at the edge — **P6-M5**.
- **The "deploying a Streamable HTTP server" howto section** — **P6-M7**.
- **Multi-tenant** (one Cowboy listener routing across multiple `erlmcp_server`s)
  — keep it one-listener-per-server.
- **TLS / auth / CORS** — out of scope unless trivial to wire optionally.
- **Touching the session core, `erlmcp_server`, or the stdio transport** —
  these are M1/M2 work; if a P6-M4 requirement seems to need them changed,
  **escalate** before touching.

## Done when

All 21 ledger rows have a final Status + Evidence; the responder seam carries
the two new kinds; per-server Cowboy listener + endpoint handler + session
manager + SSE adapter are in place; resumability via `Last-Event-ID` works;
session lifetime is decoupled from connection lifetime; concurrent multi-client
correctness holds; deep paths (tasks/sampling) work over HTTP; the stub is
deleted; both transports green on the same spine; `make check` green; dialyzer
clean on 27 and 28 with zero suppressions; CI green; the closed ledger is
submitted for CDC review.
