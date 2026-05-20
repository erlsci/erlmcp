# Phase 0 — MCP Capability Rubric (the paradigm-neutral yardstick)

**Purpose.** Both rmcp (Rust) and erlmcp (Erlang) are *projections* of the MCP
specification onto a host language. To compare them fairly we must not measure
erlmcp against Rust idioms; we measure both against the spec. This document is
that yardstick: an enumeration of what the protocol requires, organized into
layers, plus the quality dimensions a "high-quality" SDK should satisfy.

Everything downstream (Phase 2 idiomatic projection, Phase 3 gap analysis,
Phase 4 plan) scores against the matrices defined here.

---

## 1. Target specification version

rmcp tracks **`2025-11-25`** as `ProtocolVersion::LATEST`, with negotiated
backward compatibility to `2025-06-18`, `2025-03-26`, and `2024-11-05`
(evidence: `phase1-rmcp-audit.md`, model/capabilities + version constants).

**Decision for erlmcp 0.6.0:** target `2025-11-25` as the headline version, and
treat *protocol-version negotiation itself* as a first-class feature (accept a
client's older version and respond in kind, within a supported set). This is a
capability erlmcp 0.5.0 does not have and rmcp does — see Phase 3.

A subtlety worth respecting: the spec version is a *negotiated* value carried in
`initialize`, not a compile-time constant. The SDK should expose the set of
supported versions and pick the highest mutually supported one.

---

## 2. Layered capability model

The protocol decomposes cleanly into five layers. The value of the layering is
that it tells us *where* a given Erlang process/module boundary should fall.

### L0 — Wire / JSON-RPC 2.0

The transport-agnostic message envelope. Everything else rides on this.

| Capability | Notes |
|---|---|
| Request objects | `id`, `method`, `params`; id is string or number, must be unique per session |
| Response objects | `id` + exactly one of `result` / `error` |
| Notification objects | `method` + `params`, **no** `id`, no response |
| Error objects | `code` (integer), `message`, optional `data` |
| Standard error codes | parse (-32700), invalid request (-32600), method not found (-32601), invalid params (-32602), internal (-32603) + MCP-specific codes |
| Batching | array of messages (de-emphasized in recent spec, but must be parsed gracefully) |
| ID correlation | match responses to in-flight requests; handle unknown/duplicate ids |

### L1 — Lifecycle

| Capability | Method | Direction |
|---|---|---|
| Initialize handshake | `initialize` | client → server |
| Capability negotiation | (in initialize result) | both advertise capabilities |
| Protocol-version negotiation | (in initialize params/result) | pick highest mutual |
| Initialized signal | `notifications/initialized` | client → server |
| Liveness | `ping` | either direction |
| Shutdown | transport close | either |

### L2 — Server features (server exposes to client)

| Feature | Methods | Notifications |
|---|---|---|
| **Tools** | `tools/list`, `tools/call` | `notifications/tools/list_changed` |
| **Resources** | `resources/list`, `resources/read`, `resources/templates/list`, `resources/subscribe`, `resources/unsubscribe` | `notifications/resources/updated`, `notifications/resources/list_changed` |
| **Prompts** | `prompts/list`, `prompts/get` | `notifications/prompts/list_changed` |
| **Completion** | `completion/complete` | — |
| **Logging** | `logging/setLevel` | `notifications/message` |

Tool details that matter for fidelity: input schema (JSON Schema), **output
schema + structured content**, content item types (text / image / audio /
embedded resource / resource link), tool annotations (read-only, destructive,
idempotent hints), and the ability to signal `list_changed` when the toolset
mutates at runtime.

Resource details: direct resources vs **resource templates** (URI templates
with variables), subscription lifecycle, and both `updated` and `list_changed`
notification flavors.

### L3 — Client features (client exposes to server)

These invert the usual direction — the *server* calls the *client*. An SDK that
only does "server answers client" is half a protocol implementation.

| Feature | Method | Direction |
|---|---|---|
| **Roots** | `roots/list` | server → client |
| Roots changed | `notifications/roots/list_changed` | client → server |
| **Sampling** | `sampling/createMessage` | server → client |
| **Elicitation** | `elicitation/create` | server → client |

Elicitation detail: form/schema-based input requests with validation, plus
URL-mode and completion — the server asks the *user* (via the client) for
structured data mid-tool-call.

### L4 — Cross-cutting concerns

These thread through every request and are easy to under-implement.

| Capability | Mechanism |
|---|---|
| **Progress** | `notifications/progress` keyed by a `progressToken` carried in request `_meta` |
| **Cancellation** | `notifications/cancelled` referencing an in-flight request id |
| **Pagination** | opaque `cursor` in list params + `nextCursor` in results |
| **`_meta`** | arbitrary metadata channel on requests/results |
| **Tasks** | long-running work: `tasks/get`, `tasks/list`, `tasks/result`, `tasks/cancel` + per-tool task support (newer SEP; rmcp implements it) |
| **Icons** | resource/tool icon metadata |
| **Structured content** | typed tool output validated against an output schema |

---

## 3. Capability matrix template

Phase 3 fills this in for both libraries. Scoring per cell:
**✓** full · **◑** partial · **✗** absent · **n/a** not applicable to that role.

```
Layer / Feature            | rmcp (cli/srv) | erlmcp 0.5 (cli/srv) | ideal erlmcp 0.6
---------------------------+----------------+----------------------+------------------
L0 JSON-RPC envelope       |                |                      |
L0 error codes             |                |                      |
L0 batching (parse)        |                |                      |
L1 initialize/negotiation  |                |                      |
L1 version negotiation     |                |                      |
L1 ping                    |                |                      |
L2 tools (+output schema)  |                |                      |
L2 resources (+templates)  |                |                      |
L2 resource subscribe      |                |                      |
L2 prompts                 |                |                      |
L2 completion              |                |                      |
L2 logging                 |                |                      |
L3 roots                   |                |                      |
L3 sampling                |                |                      |
L3 elicitation             |                |                      |
L4 progress                |                |                      |
L4 cancellation            |                |                      |
L4 pagination              |                |                      |
L4 tasks                   |                |                      |
L4 structured content      |                |                      |
```

---

## 4. Quality dimensions (the bar, not just the checklist)

Feature coverage is necessary but not sufficient. The four axes below are the
ones the project owner explicitly wants erlmcp to match rmcp on. Each gets a
concrete definition so Phase 3/4 can hold the design to it.

**A. Ergonomic tool/handler API.** How little boilerplate does a user write to
expose a tool/resource/prompt? rmcp's bar: a single annotated impl block, schema
auto-derived from types, name from the function. The Erlang equivalent must hit
a comparable "define the handler, the wiring is automatic" bar *without* relying
on compile-time macros (see Phase 2 — this is the central design problem).

**B. Correctness & safety.** Hard-to-misuse APIs, validation at the boundary
(input *and* output schemas actually enforced), predictable error behavior, and
type discipline (here: `-spec`/`-type` coverage + Dialyzer-clean, the Erlang
analogue of Rust's type-driven correctness).

**C. Architecture & modularity.** Clean separation of wire / lifecycle /
transport / feature-handler / dispatch layers; pluggable transports and
pluggable handlers behind stable behaviours; no God modules; supervision tree
that maps to the protocol's failure domains.

**D. Coverage, docs & conformance.** Breadth of L0–L4 coverage; quality of docs
and runnable examples; and — the artifact erlmcp most conspicuously lacks — a
**conformance harness with dated, versioned scorecards** measuring the SDK
against the spec (rmcp ships exactly this; server 87.5% / client 80%). 0.6.0
should treat "we can measure our own conformance" as a deliverable.

---

## 5. How to read the rest of the analysis

- **Phase 1 / 1b** (done): factual audits of rmcp and erlmcp 0.5.0.
- **Phase 0-erlang-rubric** (parallel): the idiomatic-Erlang house style, from
  the Inaka/nuex guides, that constrains *how* we may realize each capability.
- **Phase 2**: for every capability above, the chosen OTP realization — and the
  explicit calls for where Erlang should *diverge* from rmcp rather than
  transliterate it.
- **Phase 3**: the matrix in §3 filled in, deltas classified.
- **Phase 4**: the sequenced 0.6.0 plan.
