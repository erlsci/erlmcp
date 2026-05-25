# erlmcp 0.6.0

**A complete, clean-room re-core of the Erlang/OTP Model Context Protocol SDK.**

0.6.0 rebuilds erlmcp from the ground up around a `gen_statem` session with a
per-request-process spine — matching the Rust reference SDK (rmcp) on quality and
exceeding it where the BEAM is genuinely stronger. It targets the **2025-11-25** MCP
protocol and ships a symmetric client and server, four transports behind one behaviour,
and supervised long-running tasks.

> **Breaking:** this is a full re-core; the 0.5.x API is **not** preserved. See the
> [Migration Guide](MIGRATION-0.5-to-0.6.md). Requires **Erlang/OTP 25+**.

## Highlights

**Full server surface.** Tools (with input/output schema validation via `jesse`,
structured content, all five content types, annotations, runtime `list_changed`);
resources (list/read, RFC-6570 level-1 templates, subscribe/unsubscribe, `updated` +
`list_changed`); prompts (list/get + `list_changed`); logging (`setLevel` +
level-filtered `notifications/message`); completion; and cursor/`nextCursor` pagination
across every list endpoint.

**Symmetric client.** `erlmcp_client_session` consumes the full request surface
(tools/resources/prompts/logging/completion, pagination, progress receipt, cancellation
issuance) **and** provides the inverted-direction features: server-initiated
**sampling** end-to-end, **roots**, and **elicitation** as client callbacks, plus task
consumption (`tasks/get|list|result|cancel`).

**Four transports, one behaviour.** `stdio`, `tcp`, `http` (HTTP + SSE), and
`streamable_http` all implement `erlmcp_transport` and deliver to their bound session
identically — the session stays transport-agnostic, proven by a parameterized
conformance suite running the same example server over each.

**Native-strength features.** Where the BEAM lets erlmcp do better than a typical SDK:

- **Per-request fault isolation** — every in-flight request runs in its own monitored
  worker; a crashing handler becomes a `-32603` and the session survives, with no
  head-of-line blocking.
- **Cancellation *is* process termination** — `notifications/cancelled` (and task
  cancel) kill the worker; no late result, no token bookkeeping.
- **Supervised long-running tasks** — `tasks/*` backed by real supervised processes;
  pollable, cancellable mid-flight, progress over `notifications/progress`.

**Tool discoverability (erlmcp extension).** An optional, explicitly non-protocol layer:
wayfinding metadata (`when_to_use`/`next`/`category`/…) declared on the single
`add_tool/2` registration map and *derived* into three surfaces — `InitializeResult.instructions`,
per-tool `_meta` (reverse-DNS `io.erlmcp/`), and a generated directory tool — so they
cannot drift. Protocol-native carriers wherever possible; the directory tool is the one
labeled extension and is excluded from the conformance scorecard.

## Quality

- **Conformance:** 100% across server, client, and transport scenarios (L0–L4) — above
  the rmcp reference (87.5%). A dated, versioned scorecard is published under
  `conformance/results/`.
- **Coverage:** 94% aggregate, **every module ≥90%**, exclusion list empty.
- **Tests:** 544 — EUnit (units) + Common Test (lifecycle/transport/e2e) + PropEr
  (envelope + state-machine fuzzing).
- **Static:** Dialyzer clean, xref clean, `-spec`/`-type` on all exports.
- **Pre-release code audit:** complete, all findings resolved (0 open).

## Breaking changes / migration

The 0.5.x modules `erlmcp_server`, `erlmcp_stdio_server`, and `erlmcp_client` are
removed; `erlmcp_server_session` / `erlmcp_client_session` and the `erlmcp` facade
replace them. The [Migration Guide](MIGRATION-0.5-to-0.6.md) gives the API mapping and
porting steps for both server and client.

## Install

```erlang
%% rebar.config
{deps, [
    {erlmcp, {git, "https://github.com/erlsci/erlmcp.git", {tag, "0.6.0"}}}
]}.
```

## Documentation

[Architecture](../architecture.md) · [Protocol](../protocol.md) ·
[OTP patterns](../otp-patterns.md) · [API reference](../api-reference.md) ·
[Migration guide](MIGRATION-0.5-to-0.6.md)

## What's next

Post-0.6 work is tracked in
[`planning/M7-post-0.6-backlog.md`](planning/M7-post-0.6-backlog.md): a 0.6.x polish
pass (further `server_session` decomposition, concurrent batch dispatch, `request_peer`
peer-death fast-fail) and 0.7 features (OAuth 2.1 client, distributed registry,
telemetry). The discoverability/extension surface will be dogfooded by a graph-RAG
extension in 0.6.1.

---

*Release discipline: SemVer + these notes + the git history (no hand-maintained
CHANGELOG).*
