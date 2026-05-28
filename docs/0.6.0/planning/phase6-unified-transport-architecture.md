# Phase 6 — Unified transport architecture (server/session split + Cowboy Streamable HTTP)

> Strategy & design for the Phase 6 re-core-within-the-re-core. Phase 6 fixes a
> structural defect carried since 0.5.0 and rebuilds the transport layer so that
> **stdio** and **Streamable HTTP** share one transport-agnostic spine, with
> branch-specific code only where the two transports genuinely differ.
>
> A correct, spec-conformant Streamable HTTP server is a **hard blocker on
> 0.6.0** (decision, this phase). Engineering order, not preservation order:
> nothing in 0.6.0 is depended on yet, so we break whatever needs breaking to
> reach the best-engineered result.

## 0. Status & origin

This phase was scoped in a CDC ↔ Duncan design session that began as a narrow
"the connector shows no tools" stdio bug and pulled up, by stages, into an
architectural review. The trail:

- The "no tools available" symptom was payload non-conformance (invalid `Icon`,
  bad `taskSupport` enum, missing `/utf8`) — see `docs/debugging/empty-tools-symptom.md`.
- Underneath sat a **startup race** (the stdio reader begins reading before the
  example finishes registering tools), which forced the question "what is the
  *right* OTP startup discipline here?"
- That question exposed three coupled, deeper defects (see §1) that no point-fix
  resolves. Phase 6 is the response.

## 1. Why Phase 6 — the defect

Three defects, coupled, all rooted in a single stdio-shaped assumption: **one
server = one session = one connection = one reply destination.** That holds for
stdio forever and for HTTP never.

### 1.1 Catalog/conversation fusion (the anti-pattern)

`erlmcp_server_session` fuses two things that have different cardinality and
lifetime:

- the **catalog/config** — registered tools/resources/prompts, capabilities,
  identity. For an HTTP server this is **shared across every client session**.
- the **live conversation** — `initialized?`, negotiated protocol version,
  in-flight requests, the reply destination. This is **per client**.

For stdio (exactly one conversation) the fusion is invisible. For HTTP (N
concurrent conversations over one server) it is wrong: you would either duplicate
the catalog into every session or registration would fail to propagate. This is
the headline anti-pattern Phase 6 removes — a representative case of the 0.5.0
anti-patterns that motivated the 0.6.0 re-core in the first place. It does not
ship in 0.6.0.

### 1.2 The single-pid emit seam

Every outbound message in the session funnels to three functions
(`send_response/3`, `send_error/4`, `send_raw/2`) that all do `Transport !
{send, Json}` to **one** transport pid held in `#data.transport`. Progress
(`erlmcp_ctx:report_progress/3`) and server→client requests
(`erlmcp_ctx:request_peer/3`) both route *back through the session* and converge
on the same seam. So the entire protocol engine is already transport-agnostic
**except for this one emit point**. Generalizing it from "a pid" to "a reply
channel" is the pivot the whole unification turns on.

### 1.3 The stdio-shaped HTTP stub

`erlmcp_transport_streamable_http` is stdio's shape in an HTTP coat: one
gen_server owning the listen socket, **busy-polling** `gen_tcp:accept/2` inside
its own message loop, forwarding every connection's bytes to **one** bound
session, and replying to the *most-recently-accepted* socket (misrouting under
concurrency). No SSE, no `Mcp-Session-Id`, no per-client session, no body
assembly past one TCP segment. It is not the Streamable HTTP transport the MCP
2025 spec describes. It is scrapped.

### 1.4 The startup race (symptom, not cause)

`start_stdio_setup/2` starts the transport (whose reader begins reading stdin
immediately) and *then* returns to caller code that registers tools — so the
client's `tools/list` can be answered against a half-built catalog. This is a
symptom of building the server imperatively in the caller rather than wiring it
as a supervised unit that is *fully configured before it serves*. Phase 6 closes
it structurally (catalog built in the server before `serve`; a `serve/1`
go-live gate) rather than with a point-fix.

## 2. Mandate & principles

- **Streamable HTTP is in scope for 0.6.0 and must be correct.** No shipping the
  stub, no "experimental" label as a way to dodge the work.
- **Maximal reuse, branch only where transports differ.** One spine; per-transport
  code confined to framing, connection management, and the reply-channel kind.
- **Lean on Cowboy maximally.** Cowboy owns the acceptor pool, HTTP parsing,
  connection-process lifecycle, and SSE transport mechanics. We build only the
  MCP semantics on top. Do not hand-roll what Cowboy already does.
- **Engineering order, not preservation order.** No sacred cows. Keep only the
  good parts; scrap anything in the way. 0.6.0 has no external users yet, so the
  tree may stay broken across milestones while the correct structure is built.
- **Locked decisions carry forward:** JSON via `jsx` behind `erlmcp_codec` only;
  schema validation via `jesse`; minimum OTP 25+; coverage gate 90% scoped via
  `cover_excl_mods`; validate at the edge, crash in the interior; opaque types,
  no shared records across boundaries; one way to do a thing, no `_new` forks; no
  hand-maintained CHANGELOG.
- **New accepted dependency:** `cowboy` (and its `ranch` dependency), introduced
  in P6-M4. This is an amendment to the dependency set (previously `jsx` +
  `jesse`); recorded here and in the M3 ledger.

## 3. Target architecture

Three transport-agnostic abstractions, plus per-transport tiers that do **not**
get forced onto each other.

### 3.1 `erlmcp_server` (new) — one per server

Owns identity, capabilities, and the **catalog** (tools/resources/prompts). The
catalog lives in an **ETS table owned by the server process**, read concurrently
by sessions; registration writes through the server. Read-mostly shared state is
the textbook ETS use — it keeps catalog reads (`tools/list`, `tools/call`
dispatch) off any single gen_server hot path and lets many HTTP sessions read
the same catalog without duplication. The server is the unit the configuration
describes and the unit a transport "serves."

### 3.2 `erlmcp_server_session` (refactored) — one per conversation

Reduced to a live protocol conversation: state machine
(`uninitialized → operational → shutting_down`; the dead `initializing` state is
removed), in-flight request tracking, the per-request **reply target** and the
session-level **push channel**. Reads the catalog from its `erlmcp_server` by
reference (ETS). For stdio: exactly one, lifetime = the server. For HTTP: one per
`Mcp-Session-Id`. The same session code runs for both transports — this is the
shared session abstraction.

### 3.3 `erlmcp_reply` (new) — the responder; the single branch point

An opaque value answering one question: *how do I send a binary back to the peer
for this message?* Kinds:

- `{device, WriterPid}` — stdio. `send/2` → `WriterPid ! {send, Json}`.
- `{http, ConnPid, ReqRef}` — an HTTP request/response. `send/2` →
  `ConnPid ! {jsonrpc_out, ReqRef, Json}`; the Cowboy handler, blocked holding
  the POST open, writes the response and completes.
- `{sse, StreamPid}` — an SSE stream. `send/2` formats an `text/event-stream`
  event with a monotonic id and writes it to the standing stream.

The session calls `erlmcp_reply:send(Responder, Json)` and never learns the
transport kind. The per-transport divergence collapses into this module's
`send/2`. The transport (or Cowboy handler) *constructs* the responder on inbound
and *consumes* outbound by writing its socket/device.

The session holds **two** responders: a **per-request reply target** (stored in
the in-flight map it already keeps, so the async worker round-trip replies to the
originating connection) and a **session push channel** in server/session state
(for unsolicited server→client traffic — notifications, sampling). For stdio both
resolve to the one device writer; for HTTP the per-request target is the POST
connection and the push channel is the standing GET SSE stream.

### 3.4 `erlmcp_transport` behaviour (redefined)

The current behaviour (`send(state(), iodata())`, `init(TransportId, Config)`)
does not match reality — transports are gen_servers driven by a message protocol.
Redefine the contract to what is true: a transport delivers a **framed inbound
message + its responder** to a session, accepts **outbound** via the responder,
and supports a lifecycle (`init` / `serve` / `close`). This makes the behaviour
honest and gives both transports one interface to implement.

### 3.5 Per-transport tiers

- **stdio** — the degenerate case: one implicit connection, a constant responder,
  no session manager. Folded into a **per-server subtree** (server + session +
  stdio transport) that lives and dies as a unit. A `serve/1` go-live gate spawns
  the reader only after the catalog is built and the session is wired — closing
  the startup race (§1.4) by construction.
- **Streamable HTTP** — a Cowboy-based subtree: a per-server listener; an MCP
  endpoint handler for POST / GET / DELETE; an `erlmcp_http_session_mgr` mapping
  `Mcp-Session-Id → session`; an SSE responder adapter with event ids + a bounded
  replay buffer for resumability. Sessions outlive connections.

### 3.6 Lifecycle: `serve/1` and `start_phases`

The `serve/1` gate ("build fully, then serve") is the externally-triggered
go-live signal both transports use. The library/programmatic API
(`start_*_setup`) calls it for the caller (race-proof and forget-proof). At the
**release layer** — the `rebar3 release` topology the howto teaches, where the
release *is* one MCP server booted at application start — `start_phases`
(`register` then `serve` phase atoms) is the idiomatic way to sequence the same
two steps, and it calls the same `serve/1` primitive. `start_phases` is a
*consumer* of the gate at the application layer, not a replacement for it, and
cannot serve the dynamic/programmatic path (no application-start event fires for
a runtime-started server).

## 4. Shared vs divergent surface

| Concern | Shared spine (reuse) | Per-transport branch |
|---|---|---|
| Protocol/session logic | `erlmcp_server_session`, codec, json_rpc, model, handler dispatch, workers, tasks, sampling, progress | — |
| Catalog/config | `erlmcp_server` + ETS, registration | — |
| Inbound *after framing* | "complete JSON-RPC message + responder → session" | framing: stdio newline-delimited; HTTP body + SSE (Cowboy) |
| Outbound | "session emits to a responder" (`erlmcp_reply`) | routing: device vs POST-connection vs SSE stream |
| Lifecycle gating | config-driven registration + `serve/1` | what "a connection" is (none vs many) |
| Session identity | the session process itself | stdio implicit singleton; HTTP `Mcp-Session-Id` via session manager |
| Resumability | — | HTTP-only: SSE event ids + `Last-Event-ID` replay buffer |
| Termination | session shutdown path | stdio EOF; HTTP DELETE / stream close / idle timeout |

stdio is the **degenerate case** of the shared abstractions — one connection, a
constant responder — not a peer of HTTP in complexity. We share the session core,
the responder, and the framed-message contract; we do **not** force stdio through
an acceptor pool or session manager it has no use for.

## 5. HTTP specifics (the Cowboy boundary)

**Cowboy owns:** TCP acceptor pool (via ranch), HTTP/1.1+2 parsing, request/body
reading, response writing, connection-process lifecycle, and the SSE transport
(streaming/loop handlers). A Cowboy handler process *is* the connection/request
process; Cowboy owns its lifecycle. Because our sessions are separate supervised
processes that handlers talk to by message, a handler crash cannot reach a
session — the "monitors not links" concern is satisfied by construction; the only
monitor we add is the session manager watching its sessions to prune its map.

**We build (the MCP layer only):**

- **Endpoint handler** — POST (a JSON-RPC message/batch; respond `application/json`
  *or* upgrade to an SSE stream and close after the response), GET (open a standing
  SSE stream for server→client traffic), DELETE (terminate the session).
- **`erlmcp_http_session_mgr`** — mint an `Mcp-Session-Id` on `initialize`, look it
  up on subsequent requests, expire/terminate. Keyed registry distinct from
  `erlmcp_registry` (which stays a pure directory).
- **SSE responder adapter** — assign monotonic event ids; maintain a **bounded
  replay buffer** per stream; on reconnect with `Last-Event-ID`, replay events
  after that id.
- **Session GC** — idle timeout; session lifetime decoupled from any connection.
  A dropped SSE stream does **not** terminate the session.

## 6. Milestones (engineering order)

Phase 6 milestones are labelled **P6-M1 … P6-M7** to avoid collision with the
original 0.6.0 M0–M6b. Each gets its own ledger + CC prompt when it begins (the
repo's per-milestone convention); only P6-M1 is fully specified up front.

### P6-M1 — Core spine
**Goal:** the transport-agnostic spine, unit-tested, with no transport fully
wired yet. Stand up `erlmcp_server` (catalog in ETS); split
`erlmcp_server_session` down to per-conversation state reading the catalog by
reference; introduce `erlmcp_reply` (with the `{device, _}` kind); reroute every
emit through it; give the session a per-request reply target + a session push
channel; generalize `erlmcp_ctx` off the raw transport pid; redefine the
`erlmcp_transport` behaviour to the real contract; make registration
config-driven into the server; add the cheap **outbound UTF-8 well-formedness
guard** at the emit/codec boundary. **Exit:** spine unit + property tested;
dialyzer clean; coverage gate holds over the new/refactored modules.

### P6-M2 — stdio on the new shape (+ the 100% OTP launcher)
**Goal:** the first transport fully working **and launchable for testing** on the
correct architecture. Rebuild `erlmcp_transport_stdio` against the responder seam;
fold server + session + transport into a **per-server subtree**; add the `serve/1`
gate. The startup race closes structurally.

**Launcher (moved here from the old M5/M6 plan — testability is a prerequisite):**
stdio is not "working" until we can launch it to test it, and the launcher must be
**100% OTP** — the supervision tree owned by an **application controller**, not a
transient `erl -eval` process (which silently kills the tree on return). Build
`simple` as a proper OTP **application** (`{mod, …}` + `start_phases` `serve`) +
a **relx release** with `-noshell` (not `-noinput`) vm.args; `run.sh` boots the
release. The app is `permanent`, so stdin EOF → subtree down → node halt, the
OTP way. `simple` is the **reference**; calculator/weather clone it in P6-M6.

**Exit:** round-trip subprocess test green **against the release-launched
`simple`**; a "register N, `*/list` returns N" conformance test green; `initialize
→ ping → tools/list → tools/call → cancel` end-to-end over stdio; clean node exit
on stdin EOF; the `-noshell` vm.args recipe documented.

### P6-M3 — Discoverability enhancement
**Goal:** make the existing discoverability layer (already-populated
`InitializeResult.instructions` + the `directory` tool + per-tool metadata)
**README-grade on first contact.** Closes the gap CD found in
`workbench/erlmcp-discoverability-assessment.md` (and reconciled in
`docs/0.6.0/planning/phase6-discoverability-plan.md`): the spec-blessed slot is
already filled but emits a thin "Categories: …. Use tools/list." string, and the
rich per-tool semantics (`when_to_use`/`next`/protocol-feature notes) live one
tool-call deep instead of at the handshake.

**Scope — library *machinery* only; example content lands in P6-M6.**
- Enrich `erlmcp_instructions:generate/_` to README-grade output: server identity
  (name, purpose, version, source URL), category overview, entry points, **protocol
  features exercised** (sampling / tasks / progress), and an explicit pointer to
  the `directory` tool. Accept an author-supplied override.
- Add a **server-level identity block** to the `directory` tool's output (name,
  purpose, version, source, protocol features, docs pointer).
- Add a first-class **`protocol_features`** field per tool (promote
  `(exercises sampling)`-style notes out of `when_to_use` prose into a structured,
  prominent field).
- Tighten the `directory` tool's own description so its "start here / I'm the
  README" role is unmissable.

**Depends on:** CD verifying that Claude Desktop actually surfaces
`InitializeResult.instructions` to the model (the gating check in
`phase6-discoverability-plan.md` §1). If it doesn't, leverage shifts onto
descriptions + `directory`, but the machinery changes here still apply.

**Exit:** the machinery produces README-grade `instructions` from a server that
supplies identity + `protocol_features`; `directory`'s output carries a server
identity block + per-tool `protocol_features`; unit/CT coverage holds the new
fields; dialyzer clean on 27/28; `make check` green.

### P6-M4 — Streamable HTTP via Cowboy
**Goal:** the second transport, proving the abstraction generalizes. Add cowboy
(deps amendment); per-server listener; the POST/GET/DELETE endpoint handler;
`erlmcp_http_session_mgr`; the SSE responder adapter with event ids + bounded
replay buffer + `Last-Event-ID` resumability; session GC. **Exit:** concurrent
multi-client correctness (responses correlate to the originating connection); SSE
resume after a dropped stream; session expiry and DELETE; both transports green
on one shared spine.

### P6-M5 — Strict payload validation
**Goal:** the handoff §2 work on the now-stable shared edge. Generate a JSON
Schema from `schema.ts` (protocol 2025-11-25) + the SHOULD⇒MUST overlay; wire
`jesse` inbound (→ `-32600`/`-32602`) and outbound (fail closed); the
`Icon.src`/`additionalProperties:false` and `taskSupport` enum regression cases;
the list-all conformance check; CI schema drift-guard. The outbound UTF-8 custom
check (from P6-M1) is formalized here. **Note:** jesse is draft-04/06 and the
generator emits draft-07 (`const`/`anyOf`) — verify jesse digests it on OTP 25–28
or raise an amendment (do not swap jesse — locked).

### P6-M6 — Examples rehabilitation + Claude Desktop acceptance
**Goal:** the example servers on the new API, validated against a real client.
`simple` is already an OTP application + release (the reference built in P6-M2);
here, **clone that template** to rehab `calculator`/`weather` as OTP apps +
releases onto `erlmcp_server` + sessions + config-driven setup. Run the per-example
acceptance matrix; attach Claude Desktop to **both** stdio and HTTP servers.

### P6-M7 — Howto + release mechanics
**Goal:** the `docs/creating-an-mcp-server.md` greenfield tutorial (the howto idea
bank), now able to teach the correct architecture — both transports, the
`serve/1` gate, and `start_phases` at the release layer (the `-noshell` release
recipe is already proven and documented in P6-M2, §4.4 seed) — then the mechanical
release: merge task branches → `release/0.6.x` → `main`, tag 0.6.0, publish notes.

### Dependency order
P6-M1 is the keystone (M2, M3, M4, M6 all assume cheap, per-client, catalog-free
sessions). M2 proves the spine end-to-end on the simpler transport. M3 enriches
the discoverability machinery (library only; no transport coupling), so the
examples in M6 have a README-grade `instructions`/`directory` to populate. M4
takes on HTTP. M5 (strict payload validation) is transport-agnostic and could
move earlier ("validate at the edge from day one"); it is placed after the
transports because the highest-value test is "does a real client accept our
payloads," which needs them — but the cheap outbound UTF-8 guard lands in M1
regardless. M6/M7 are the release runway.

**Shift (2026-05-27):** two changes to the original ordering.
(a) The OTP application/release **launcher** moved *forward* into M2 (originally
implied in the old M5/M6). Reason: the `erl -eval` launcher killed the
application-unowned supervision tree on return, so stdio could not be tested at
all — and an untestable transport cannot be signed off or built upon. M2 now
builds **one** reference app+release (`simple`); M6 is correspondingly lighter
(clone the template to calculator/weather); M7 documents the already-proven
recipe.
(b) A new **P6-M3 — Discoverability enhancement** was inserted, after a CD
consumer-side assessment showed the spec-blessed `instructions` slot was populated
but thin. The rest of Phase 6 renumbered up by one (old M3/M4/M5/M6 →
M4/M5/M6/M7). Source: `docs/0.6.0/planning/phase6-discoverability-plan.md`.

## 7. Disposition of the existing tree

**Keep & refactor:** `erlmcp_server_session` (split), `erlmcp_codec`,
`erlmcp_json_rpc`, `erlmcp_model`, `erlmcp_schema`, `erlmcp_pagination`,
`erlmcp_uri_template`, `erlmcp_ctx` (generalize off the transport pid),
`erlmcp_task`/`erlmcp_task_sup`, `erlmcp_capabilities`, `erlmcp_instructions`,
`erlmcp_sampling`, `erlmcp_elicitation`, `erlmcp_roots`, `erlmcp_registry` (stays
a pure directory).

**New:** `erlmcp_server`, `erlmcp_reply`, `erlmcp_http_session_mgr`, the Cowboy
endpoint handler, the per-server subtree supervisor.

**Scrapped / replaced:** `erlmcp_transport_streamable_http` (the busy-poll stub) →
Cowboy-based HTTP; the flat `erlmcp_transport_sup` wiring → per-server subtrees;
the `erlmcp_transport` behaviour → redefined; `erlmcp_transport_stdio` rebuilt
onto the responder seam + `serve/1`.

**Out of scope (orthogonal):** the client-side `erlmcp_transport_tcp` and
`erlmcp_transport_http` (erlmcp acting as an MCP *client*) are untouched by this
server-transport arc.

## 8. Open sub-decisions (resolved within milestones, not now)

- Per-server subtree restart strategy (stdio): sessions/transports are currently
  `temporary` (no auto-recovery). For stdio, "session dies → process exits" is
  arguably correct; confirm and document in M2 rather than assume.
- Replay-buffer bound and SSE idle/GC timeouts (M3) — pick defaults, make
  configurable.
- Catalog ETS access pattern (M1): direct `ets:lookup` from sessions vs a thin
  `erlmcp_server` read API. Lean toward direct reads of a `protected` table owned
  by the server for hot-path reads, server-API for writes.
- Whether `erlmcp_server` is a `gen_server` or a supervisor+ETS-owner — M1 call.

## 9. Branches & CI

Integration branch `release/0.6.x`. Phase 6 milestone branches use the `task/`
prefix so CI fires: `task/0.6.0-p6m1` (cut from `release/0.6.x`, PR back), then
`-p6m2`, `-p6m3`, … CI is the independent reproducer (CDC's sandbox has no Erlang
toolchain): compile (zero warnings) + xref + eunit + CT + PropEr + dialyzer +
coverage, matrix OTP 25–28. M3 adds cowboy/ranch to the build.
