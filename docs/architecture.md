# erlmcp Architecture

## Overview

erlmcp 0.6.0 is an Erlang/OTP implementation of the Model Context Protocol
(MCP), built around a `gen_statem` session + per-request-process spine. The
architecture emphasises fault isolation, transport agnosticism, and the
principle of "validate at the edge, crash in the interior."

## Core Components

### Session Layer

Two `gen_statem` processes implement the MCP session lifecycle:

- **`erlmcp_server_session`** — server-side protocol state machine
  (`uninitialized → initializing → operational → shutting_down`). Handles
  tools, resources, prompts, logging, completion, and the discoverability
  surfaces. Can initiate outbound requests to the client (sampling, roots,
  elicitation) via the `erlmcp_ctx:request_peer/3` peer handle.

- **`erlmcp_client_session`** — client-side state machine. Issues requests
  to the server (list/call/read/get/subscribe/complete), handles inbound
  notifications, and dispatches inbound server requests to registered
  callback behaviours (`erlmcp_sampling`, `erlmcp_roots`,
  `erlmcp_elicitation`).

Both sessions accept transport data via cast or info (`{transport_data, _}`),
making them transport-agnostic.

### Per-Request Worker Isolation

Every tool call, resource read, prompt get, and callback dispatch runs in a
short-lived worker process that the session monitors. A crashing handler
produces an `'EXIT'` that the session catches and converts to a JSON-RPC
`-32603` error response. One bad request cannot take down the session.

Cancellation is process termination: `notifications/cancelled` kills the
worker. No cooperative cancellation tokens, no map to maintain.

### Transport Layer

The `erlmcp_transport` behaviour defines a uniform contract:

- **Inbound:** transport delivers data to the session via
  `Session ! {transport_data, Data}`
- **Outbound:** session sends via `Transport ! {send, Data}`
- Four implementations: `erlmcp_transport_stdio`, `_tcp`, `_http`,
  `_streamable_http`

The session never knows which transport it's on.

### Registry

`erlmcp_registry` (gen_server) handles discovery and binding only — no
per-message routing on the hot path. Once a connection is established,
the session talks to its transport directly.

### Schema & Validation

`erlmcp_schema` provides a composable builder for JSON Schema maps,
validated by `jesse` at the session boundary before dispatch. Input args
are validated before the handler runs; structured output is validated
before the response is sent.

## Supervision Tree

```
erlmcp_sup (one_for_all)
├── erlmcp_registry          (gen_server)
├── erlmcp_server_sup        (simple_one_for_one → server sessions)
├── erlmcp_session_sup       (simple_one_for_one → sessions)
└── erlmcp_transport_sup     (one_for_one → transports)
```

## Discoverability

Tool metadata (`category`, `when_to_use`, `returns`, `next`) lives on the
registration map (the single source of truth) and is projected into three
surfaces:

1. **`instructions`** (Tier 0) — strategy + categories, returned at
   `initialize`
2. **`_meta`** (Tier 1) — per-tool wayfinding under `io.erlmcp/` prefix in
   `tools/list`
3. **Directory tool** (Tier 2) — optional, categorised projection

## Conformance

The `erlmcp_conformance` module runs L0–L4 server, client, and transport
scenarios. The published scorecard is at `conformance/results/`.
