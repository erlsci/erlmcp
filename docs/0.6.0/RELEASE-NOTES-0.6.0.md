# erlmcp 0.6.0

**A complete, clean-room re-core of the Erlang/OTP Model Context Protocol SDK.**

0.6.0 rebuilds erlmcp from the ground up around a `gen_statem` session with a
per-request-process spine. It targets the **MCP 2025-11-25** protocol specification
and ships a symmetric client and server, four transports behind one behaviour, strict
payload validation at the edge, and a discoverability layer that surfaces tool
catalogs to models without hand-authored prose.

> **Breaking:** this is a full re-core; the 0.5.x API is **not** preserved. See the
> [Migration Guide](MIGRATION-0.5-to-0.6.md). Requires **Erlang/OTP 25+**.

---

## What shipped

### P6-M1 — Core spine

The central architectural decision of 0.6.0: separate the per-server **catalog**
(`erlmcp_server`, ETS-backed, one per server) from the per-conversation **session**
(`erlmcp_server_session`, one per connected client). This split is what makes HTTP
possible — an HTTP server shares one catalog across N simultaneous client sessions
without duplication or registration races.

- `erlmcp_server`: `gen_server` owning a protected ETS table; config-driven
  registration of tools, resources, prompts, resource templates.
- `erlmcp_server_session`: `gen_statem` with three lifecycle states
  (`uninitialized → operational → shutting_down`); per-request supervised workers;
  responder seam via `erlmcp_reply`.
- `erlmcp_reply`: opaque responder type; the only path for outbound messages; outbound
  UTF-8 well-formedness guard at the emit boundary.
- **Per-request fault isolation**: every in-flight request runs in its own monitored
  worker; a crashing handler becomes a `-32603` and the session survives, with no
  head-of-line blocking.
- **Cancellation is process termination**: `notifications/cancelled` kills the worker
  process; no cooperative polling, no late results.

### P6-M2 — stdio transport rebuild

The stdio transport rebuilt on the responder seam with a clean `serve/1` gate that
prevents the startup race (the original cause of "no tools available"). OTP
application + release pattern established as the reference for all examples.

- `erlmcp_transport_stdio`: read loop in its own monitored process; delivers decoded
  JSON-RPC messages to the bound session.
- `erlmcp_stdio_sup`: one-for-all supervisor owning server + transport + session as
  siblings; `serve/1` gate delays stdio reads until the supervision tree is fully up.
- Reference OTP application/release layout (`simple` example) with `start_phases`
  and a `-noshell` launcher; the pattern the howto teaches.
- Tested cross-node (Erlang distribution) to verify the session is node-local.

### P6-M3 — Discoverability machinery

An optional, non-protocol extension layer for model-facing discoverability. All three
surfaces (`InitializeResult.instructions`, per-tool `_meta`, generated `directory`
tool) are derived from the same source declarations — they cannot drift.

- Identity block: `name`, `version`, `purpose`, `source`, `docs` fields in the server
  config flow into `instructions` and the directory tool automatically. No
  hand-authored prose required.
- Wayfinding fields on tool declarations: `category`, `when_to_use`, `entry_point`,
  `next`, `returns`, `summary`.
- `protocol_features` field: declares which advanced protocol features a tool
  actually exercises; appears in `_meta` under `io.erlmcp/protocol_features`.
- `erlmcp_instructions`: auto-generates a README-grade `instructions` string from
  the server's identity + tool catalog with no author override.
- Generated `directory` tool: returns a structured JSON listing of all categories,
  tools, wayfinding, and protocol features. DISC invariants (DISC-1/2/3) are
  CI-enforced: 100% tool metadata coverage, dangling-free `next` graph,
  orphan-free reachability.

### P6-M4 — Streamable HTTP via Cowboy

The second transport on the shared spine. Same `erlmcp_transport` behaviour as
stdio; the session stays transport-agnostic.

- `erlmcp_http_handler`: Cowboy request handler for POST / GET / DELETE per the
  Streamable HTTP spec.
- `erlmcp_http_session_mgr`: session registry, GC, and bounded SSE replay buffer
  (`Last-Event-ID` resumability).
- `erlmcp_http_sse`: Server-Sent Events responder adapter with event IDs.
- Multi-client correctness: concurrent sessions over one server; responses
  correlate to the originating connection.
- Parameterized transport conformance suite: the same example server runs over
  each transport; all four pass at 100%.

### P6-M5 — Strict payload validation

Schema-driven inbound and outbound validation using `jesse`. The SHOULD→MUST overlay
converts protocol ambiguities into hard enforcement, specifically targeting the three
payload bugs that caused the original "no tools available" failure.

- JSON Schema generated from the MCP 2025-11-25 TypeScript types + a SHOULD→MUST
  overlay for `Icon.src`, `taskSupport` enum, and UTF-8 well-formedness.
- Inbound: invalid JSON-RPC envelope → `-32600`; params failing `inputSchema` →
  `-32602`.
- Outbound: fail-closed; handler result failing shape check → `-32603` (the session
  returns an error rather than sending a malformed response).
- Schema drift-guard in CI: a test suite detects if the committed schema diverges
  from what the generator would produce.
- Named regression cases: Icon shape (§1.3), `taskSupport` enum (§1.5), UTF-8
  (§1.4) — each has a dedicated regression test.

### P6-M6 — Examples rehabilitation + discoverability acceptance

The three example servers (`simple`, `calculator`, `weather`) rehabilitated onto
the 0.6.0 API with full discoverability content.

- Identity blocks: real `purpose` strings and `source` GitHub URLs on all three
  examples.
- `protocol_features` declarations: honest — each matches what the handler
  actually does (calculator `slow_compute` → `[tasks, progress]`; calculator
  `explain` → `[sampling]`; weather template → `[completion]`).
- Model-facing READMEs: each example's README has a "What this server is for"
  section and a "Tool orientation" section for the model reader.
- `instructions_readable` CTs: verify auto-generated instructions contain server
  name + directory pointer without author overrides.
- Original bug shapes verifiably gone from all examples (`type => emoji` / 
  `taskSupport => allowed` grep clean).
- Claude Desktop acceptance procedure documented in
  `docs/0.6.0/acceptance/phase6-claude-desktop-acceptance.md`.

### P6-M7 — Howto + release mechanics

- `docs/creating-an-mcp-server.md`: greenfield step-by-step tutorial; builds a
  working server from zero, covering tools/resources/prompts, discoverability,
  validation at the edge, and Claude Desktop connection.
- This release notes document, finalized.
- Migration guide, finalized.
- Version bumped to 0.6.0.

---

## Quality

| Metric | Value |
|--------|-------|
| Conformance — server | 100% (ref: rmcp 87.5%) |
| Conformance — client | 100% (ref: rmcp 87.5%) |
| Conformance — transport | 100% |
| EUnit tests | 488 |
| CT tests | 224 (2 skipped: require live Claude Desktop) |
| PropEr properties | 9 |
| Line coverage | 93% aggregate; all included modules ≥90% |
| Dialyzer | clean on OTP 27 and 28 |
| xref | clean |
| Compiler warnings | zero (`warnings_as_errors` on) |

Coverage note: `erlmcp_transport_tcp` and `erlmcp_transport_http` (client-side
transports, used when erlmcp acts as an MCP *client*) are excluded from the
coverage gate via `cover_excl_mods`. All other modules meet the 90% floor.

Conformance scorecard: `conformance/results/erlmcp-0.6.0-2026-05-24.txt`.

---

## Deferred to 0.6.x

Items that were considered for 0.6.0 but descoped. They are not bugs; they are
bounded extensions.

- **Per-tool `inputSchema` validation on `tools/call`** — the current M5 gate
  validates the request envelope and method-level params; per-tool input validation
  on the dispatch path is a 0.6.1 candidate.
- **`weather_app.erl` typed server accessor** — the weather OTP app's
  `start/2` reaches through `supervisor:which_children` to register the resource
  template; this crosses the `erlmcp_server:server()` opaque boundary, causing a
  dialyzer warning in the `weather` profile. Fix: add a typed accessor to
  `erlmcp_stdio_sup`. Targeted 0.6.1.
- **Claude Desktop acceptance verdicts** — the three examples have documented
  acceptance procedures; the verdicts (`pass` / `partial` / `fail`) require
  human execution against a running Claude Desktop instance and must be recorded
  before 0.6.0 is tagged (see release checklist).
- **Further `server_session` decomposition** — the session gen_statem handles all
  inbound methods; a future pass could dispatch to domain handlers. Post-0.6.
- **Concurrent batch dispatch** — requests in a batch run serially today; true
  parallel dispatch is a post-0.6 optimization.
- **`request_peer` peer-death fast-fail** — sampling requests do not detect
  client disconnect proactively. Post-0.6.

## Out of scope for 0.6.0

- OAuth 2.1 client (0.7 target)
- Distributed registry across BEAM nodes (0.7 target)
- Telemetry / OpenTelemetry integration (0.7 target)
- Graph-RAG extension (first 0.6.x extension, slated for 0.6.1)

---

## Breaking changes / migration

The 0.5.x modules `erlmcp_server` (the old server), `erlmcp_stdio_server`, and
`erlmcp_client` are replaced. See [Migration Guide](MIGRATION-0.5-to-0.6.md) for
the full API mapping and porting steps.

## Install

```erlang
%% rebar.config
{deps, [
    {erlmcp, {git, "https://github.com/erlsci/erlmcp.git", {tag, "0.6.0"}}}
]}.
```

Requires OTP 25+. Tested on OTP 25, 26, 27, 28 (CI matrix).

---

*Release discipline: SemVer + these notes + the git history (no hand-maintained
CHANGELOG). The git log and this document are the complete record.*
