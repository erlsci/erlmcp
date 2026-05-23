# MCP Protocol Implementation

erlmcp implements the MCP 2025-11-25 protocol specification.

## Protocol Basics (L0)

- **`initialize`** — version negotiation, capability exchange, server info
- **`ping`** — liveness check
- **`notifications/initialized`** — client signals ready
- **`notifications/cancelled`** — cancels an in-flight request

## Tools (L1)

- **`tools/list`** — paginated listing with `inputSchema`, `annotations`, `_meta`
- **`tools/call`** — runs a tool handler in a per-request worker; input
  validated against `inputSchema` via `jesse` before dispatch

## Resources (L2)

- **`resources/list`** — paginated listing of static resources
- **`resources/read`** — reads resource contents by URI
- **`resources/templates/list`** — lists URI templates (level-1 expansion)
- **`resources/subscribe`** / **`unsubscribe`** — subscribe to resource updates
- **`notifications/resources/updated`** — server notifies on resource change
- **`notifications/resources/list_changed`** — server notifies on add/remove

## Prompts (L3)

- **`prompts/list`** — paginated listing with argument definitions
- **`prompts/get`** — renders a prompt with arguments into messages
- **`notifications/prompts/list_changed`** — server notifies on add/remove

## Logging (L3)

- **`logging/setLevel`** — sets the minimum log level
- **`notifications/message`** — server emits log messages at or above level

## Completion (L4)

- **`completion/complete`** — returns completions for prompt arguments or
  resource template parameters

## Server-to-Client (L4)

- **`sampling/createMessage`** — server requests an LLM completion from the
  client via `erlmcp_ctx:request_peer/3`
- **`roots/list`** — server queries the client's root URIs
- **`elicitation/create`** — server requests user input from the client

## Discoverability

Protocol-native surfaces (no extensions required):

- **`instructions`** — free-form server guidance in the `initialize` response
- **`_meta`** — per-tool wayfinding metadata (`io.erlmcp/category`,
  `io.erlmcp/when_to_use`, `io.erlmcp/returns`, `io.erlmcp/next`)
- **`annotations`** — behavioral hints (`readOnlyHint`, `destructiveHint`,
  `idempotentHint`, `openWorldHint`, `title`)

The **directory tool** is an erlmcp extension (Tier 2), excluded from the
conformance scorecard (DISC-6).

## Capabilities

Capabilities are derived from registrations, not hardcoded:

- `tools` + `listChanged` — when tools are registered
- `resources` + `subscribe` + `listChanged` — when resources/templates exist
- `prompts` + `listChanged` — when prompts are registered
- `logging` — always (handler always exists)
- `completions` — always (handler always exists)
- `sampling` / `roots` / `elicitation` — client-side, when handler registered

## Pagination

All list endpoints use opaque cursor-based pagination (`cursor`/`nextCursor`).
The client's `list_tools/1`, `list_resources/1`, etc. auto-follow cursors.
