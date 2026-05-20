# Phase 1 Audit: The Official Rust MCP SDK (`rmcp`)

A factual inventory of the `rmcp` crate as it exists in
`/Users/oubiwann/lab/erlsci/erlmcp/workbench/rmcp`. This is a catalogue, not a
set of recommendations. Where useful, each item separates **the MCP capability**
(paradigm-neutral) from **the Rust mechanism** used to express it, to support a
later re-realization in Erlang.

Version audited: workspace + crate version **1.7.0** (`Cargo.toml:12`,
`crates/rmcp/CHANGELOG.md` top entry `1.7.0 - 2026-05-13`). Rust edition 2024.
License Apache-2.0. (Note: the conformance assessment doc is older and references
v0.16.0; the live tree is 1.7.0.)

---

## 1. Crate / Module Decomposition

### 1.1 Workspace layout (`/Cargo.toml`)

`members = ["crates/rmcp", "crates/rmcp-macros", "examples/*", "conformance"]`,
`default-members` is the two library crates.

| Crate | Purpose |
|---|---|
| `crates/rmcp` | The SDK library: protocol model, service runtime, handler traits, transports, task manager, errors. |
| `crates/rmcp-macros` | Proc-macro crate: `#[tool]`, `#[tool_router]`, `#[tool_handler]`, `#[prompt]`, `#[prompt_router]`, `#[prompt_handler]`, `#[task_handler]`. |
| `examples/*` | Independent example crates (servers, clients, transport demos, simple-chat-client, wasi). |
| `conformance` | A `[[bin]]` harness used to run the official MCP conformance suite; results captured in `conformance/results/*.md`. |

### 1.2 `crates/rmcp/src` top-level modules (`lib.rs`)

| Path | Role |
|---|---|
| `error.rs` | Error model. Re-exports `ErrorData` (the wire error), defines `RmcpError` (unified runtime error), keeps deprecated `Error` alias. |
| `model.rs` + `model/` | All MCP/JSON-RPC types, serde + JSON Schema derivation, version constants, capability negotiation. The protocol's data plane. |
| `service.rs` + `service/` | The runtime: `Service`/`Peer`/`ServiceRole` abstractions, the message-pump (`serve_inner`), request/notification dispatch, cancellation, timeouts. Gated on `client`/`server` features. `service/client.rs` = `RoleClient`, `service/server.rs` = `RoleServer`, `service/tower.rs` = tower integration. |
| `handler.rs` + `handler/` | User-facing handler traits and the router/macro ergonomics. `handler/client.rs` (`ClientHandler`), `handler/server.rs` (`ServerHandler`), `handler/server/router/` (tool & prompt routers), `handler/server/wrapper/` (`Parameters`, `Json`), `handler/server/tool_name_validation.rs`. |
| `transport.rs` + `transport/` | The `Transport` trait, `IntoTransport` adapter, and all concrete transports. |
| `task_manager.rs` | Server-side async task execution engine (`OperationProcessor`) for SEP-1319/1730 tasks. `server`-feature only. |

The crate re-exports `schemars`, `serde`, `serde_json`, and (with `macros`) the
proc macros and `pastey::paste`.

---

## 2. MCP Feature Coverage

Evidence is concentrated in `model.rs` (method/type definitions), the union enums
`ClientRequest`/`ServerRequest`/`ClientNotification`/`ServerNotification`/
`ClientResult`/`ServerResult` (`model.rs:3269-3392`), and the handler dispatch in
`handler/server.rs` and `handler/client.rs`.

### Coverage table

| MCP feature | Client | Server | Module / evidence |
|---|---|---|---|
| Initialization / lifecycle | sends `initialize` | handles `initialize` | `InitializeRequest`/`InitializeResult` (`model.rs:787,851`); `initialize()` handler |
| Capability negotiation | builder | builder | `ClientCapabilities`/`ServerCapabilities` (`model/capabilities.rs`) |
| Protocol version negotiation | yes | yes | `ProtocolVersion` (`model.rs:138-200`), negotiation tests in `tests/test_streamable_http_protocol_version.rs` |
| Ping | send + handle | send + handle | `PingRequest` (`model.rs:1098`), `ping()` on both handlers |
| Tools — list | call | serve | `ListToolsRequest`/`ListToolsResult`; `ToolRouter::list_all` |
| Tools — call | call | serve | `CallToolRequest`/`CallToolResult` (`model.rs:3017,2774`) |
| Tools — structured/typed output | parse | produce | `CallToolResult.structured_content` + `output_schema`; `CallToolResult::structured` (`model.rs:2864`) |
| Tools — text/image/audio/embedded-resource/resource-link content | parse | produce | `RawContent` enum (`model/content.rs:153`) |
| Tools — annotations / hints | parse | produce | `ToolAnnotations` (`model/tool.rs:113`) |
| Tools — list_changed notification | receive | emit | `ToolListChangedNotification`; router auto-emits on disable/enable |
| Tools — runtime enable/disable | — | yes | `ToolRouter::disable_route`/`enable_route` |
| Resources — list / read | call | serve | `ListResourcesRequest`, `ReadResourceRequest`/`ReadResourceResult` |
| Resource templates | call | serve | `ListResourceTemplatesRequest` (`model.rs:1190`), `RawResourceTemplate` |
| Resources — subscribe / unsubscribe | call | serve | `SubscribeRequest`/`UnsubscribeRequest` (`model.rs:1302,1342`) |
| Resources — updated / list_changed notifications | receive | emit | `ResourceUpdatedNotification`, `ResourceListChangedNotification` |
| Prompts — list / get | call | serve | `ListPromptsRequest`, `GetPromptRequest`/`GetPromptResult` |
| Prompts — list_changed notification | receive | emit | `PromptListChangedNotification` |
| Sampling (`sampling/createMessage`) | **handle** (client provides) | **request** (server asks) | `CreateMessageRequest` is a `ServerRequest`; `create_message()` on `ClientHandler` |
| Sampling — tools/toolChoice (SEP-1577) | yes | yes | `SamplingCapability.tools` (`model/capabilities.rs:238`), `ToolUseContent`/`ToolResultContent` |
| Elicitation (`elicitation/create`) | **handle** | **request** | `CreateElicitationRequest` is a `ServerRequest`; `create_elicitation()` on `ClientHandler`; gated by `elicitation` feature |
| Elicitation — form mode / schema validation / URL mode | yes | yes | `ElicitationCapability` (form+url), `ElicitationSchema` builder (`model/elicitation_schema.rs`), `URL_ELICITATION_REQUIRED = -32042` |
| Elicitation — complete notification | emit/recv | emit/recv | `ElicitationCompletionNotification` (`model.rs:2759`) |
| Completion (`completion/complete`) | call | serve | `CompleteRequest`/`CompleteResult` (`model.rs:2264`) |
| Logging — setLevel | call | serve | `SetLevelRequest` (`model.rs:1496`) |
| Logging — message notification | receive | emit | `LoggingMessageNotification` (`model.rs:1532`) |
| Progress notifications | both | both | `ProgressNotification` (`model.rs:1141`); client subscriber in `handler/client/progress.rs` |
| Cancellation | both | both | `CancelledNotification` (`model.rs:711`); per-request `CancellationToken` pool in `serve_inner` |
| Roots (`roots/list`) | **handle** | **request** | `ListRootsRequest` is a `ServerRequest`; `list_roots()` on `ClientHandler` |
| Roots — list_changed notification | emit | receive | `RootsListChangedNotification` |
| Pagination | yes | yes | `PaginatedRequestParams` (cursor); `next_cursor` fields on list results |
| Tasks (SEP-1319/1730): get/list/result/cancel | call | serve | `tasks/get`, `tasks/list`, `tasks/result`, `tasks/cancel` (`model.rs:3105-3163`); `task_manager.rs`; per-tool `TaskSupport` (forbidden/optional/required, `model/tool.rs:55`) |
| MCP extensions (SEP-1724) | declare | declare | `ExtensionCapabilities` map keyed `vendor/name` (`model/capabilities.rs:32`) |
| Icons | parse | produce | `Icon`/`IconTheme` (`model.rs:921-958`) on tools/resources/prompts |
| `_meta` propagation (SEP-1319) | yes | yes | `Meta` + `RequestParamsMeta`; carried in request `extensions` |
| Custom requests / notifications | both | both | `CustomRequest`/`CustomNotification`/`CustomResult` (`model.rs:679-782`); `on_custom_request` handlers |
| OAuth 2.1 authorization | yes (client) | — | `transport/auth.rs`; `auth`/`auth-client-credentials-jwt` features |

Directionality note (important for re-realization): in MCP some requests are
server→client. `rmcp` encodes this structurally: `ServerRequest` =
{Ping, CreateMessage, ListRoots, CreateElicitation, Custom}, so **the client
handler implements** `create_message`, `list_roots`, `create_elicitation`.
Everything else is client→server and handled by `ServerHandler`.

---

## 3. Wire / Protocol Layer

### 3.1 JSON-RPC modeling (`model.rs`)

- `JsonRpcMessage<Req, Resp, Noti>` is an untagged serde enum with variants
  `Request`/`Response`/`Notification`/`Error` (`model.rs:579`). Specialized as
  `ClientJsonRpcMessage` and `ServerJsonRpcMessage` (`model.rs:3340,3392`).
- `JsonRpcRequest`/`JsonRpcResponse`/`JsonRpcNotification`/`JsonRpcError`
  (`model.rs:431-490`). `JsonRpcError.id` is `Option` and omitted on parse
  errors per MCP 2025-11-25 (`model.rs:462-470`).
- The `"jsonrpc": "2.0"` literal is a zero-sized type `JsonRpcVersion2_0` produced
  by the `const_string!` macro (`model.rs:71-128`) — a reusable pattern that turns
  fixed string literals (method names, version tag, schema type tags) into typed,
  self-validating ZSTs implementing `ConstString`, `Serialize`, `Deserialize`, and
  `JsonSchema`. Every MCP method name is a `const_string!` (e.g.
  `CallToolRequestMethod = "tools/call"`).
- `RequestId` = `NumberOrString` (number or string, `model.rs:208`).
  `ProgressToken(NumberOrString)`.
- `ErrorCode(i32)` with named constants including JSON-RPC standard codes plus
  `RESOURCE_NOT_FOUND = -32002` and `URL_ELICITATION_REQUIRED = -32042`
  (`model.rs:500-510`). `ErrorData { code, message, data }` (`model.rs:519`) with
  constructor helpers (`invalid_params`, `method_not_found`, etc.).

### 3.2 Request/notification generics

`Request<M, P>`, `RequestOptionalParam`, `RequestNoParam`, `Notification<M, P>`,
`NotificationNoParam` (`model.rs:317-426`). Each concrete message is a type alias
binding the method ZST and a params struct, e.g.
`pub type CallToolRequest = Request<CallToolRequestMethod, CallToolRequestParams>`.
Requests carry an `extensions: Extensions` bag (http-crate style) that conveys
`Meta` and ambient context out-of-band of the wire params.

### 3.3 Serialization

- `serde` everywhere with `#[serde(rename_all = "camelCase")]`,
  `skip_serializing_if`, and `#[serde(untagged)]` for the message and content
  unions. Custom `Serialize`/`Deserialize` impls for `NumberOrString`,
  `ProtocolVersion`, and the `const_string!` ZSTs.
- `schemars` 1.0 (feature-gated) derives JSON Schema. The message-type schema is
  exercised by `tests/test_message_schema.rs`.
- The message-type union macro `ts_union!` (`model.rs:3219`) generates the
  untagged enums and `From` impls, mirroring TypeScript-style `export type X = A | B`.

### 3.4 Lifecycle / capability negotiation

- `InitializeRequestParams { protocol_version, capabilities, client_info, _meta }`
  and `InitializeResult { protocol_version, capabilities, server_info, instructions }`
  (`model.rs:801,851`). `ServerInfo`/`ClientInfo` aliases; `Implementation::from_build_env()`
  fills name/version from Cargo env.
- Capabilities are builder-driven with a **type-state builder** (`model/capabilities.rs:322`
  `builder!` macro): each `enable_*` flips a `const bool` generic in
  `ServerCapabilitiesBuilderState<...>`, and conditional methods such as
  `enable_tool_list_changed` are only available once the parent capability is enabled.
- Task capabilities have helpers `TasksCapability::client_default()` /
  `server_default()` and `supports_*` predicates (`model/capabilities.rs:127-191`).

---

## 4. Transports

The abstraction is the `Transport<R: ServiceRole>` trait (`transport.rs:125`):
`send` (must return a `Send + 'static` future — sends may run concurrently),
`receive` (sequential), `close`. `IntoTransport<R, E, A>` (`transport.rs:150`)
implicitly converts ergonomic inputs into a `Transport`. Blanket impls cover:
(1) `Sink + Stream` or `(Tx, Rx)` tuples, (2) `AsyncRead + AsyncWrite` or
`(R, W)` tuples, (3) any `Worker`, (4) any `Transport`.

| Transport | File / feature | Side |
|---|---|---|
| stdio / generic async-rw | `transport/io.rs` (`io::stdio`), `transport/async_rw.rs` | client + server |
| Child process | `transport/child_process.rs` (`TokioChildProcess`, `which_command`) | client (spawns server) |
| Streamable HTTP — client | `transport/streamable_http_client.rs` + `common/reqwest`, `common/client_side_sse.rs` | client |
| Streamable HTTP — server | `transport/streamable_http_server/` (`tower.rs` → `StreamableHttpService`, `session/` with `local`/`never`/`store` session managers) | server |
| Unix socket HTTP | `transport/common/unix_socket.rs` (`UnixSocketHttpClient`) | client |
| Worker | `transport/worker.rs` (`WorkerTransport`) | helper |
| Sink/Stream | `transport/sink_stream.rs` | helper (e.g. websockets) |
| WebSocket | `transport/ws.rs` | present but commented out in Cargo/transport.rs (disabled) |
| OAuth auth layer | `transport/auth.rs`, `common/auth/` | client-side authorization wrapper |

Streamable HTTP server supports SSE multi-streaming, session stores for
resumability (`session/store.rs`, added in 1.6.0), Host/Origin validation, and
JSON-vs-SSE response modes (numerous dedicated tests under `tests/test_streamable_http_*`).
The legacy plain-SSE transport exists on the client/server SSE paths via
`sse-stream`.

---

## 5. Service / Runtime Model

### 5.1 Roles and the `ServiceRole` trait (`service.rs:104-121`)

`ServiceRole` ties together the directional type families: `Req`/`Resp`/`Not`
(this side) and `PeerReq`/`PeerResp`/`PeerNot` (the other side), plus
`Info`/`PeerInfo` and `IS_CLIENT`. Two implementors:

- `RoleClient` (`service/client.rs:144`): `Req = ClientRequest`,
  `PeerReq = ServerRequest`, etc.
- `RoleServer` (`service/server.rs:31`): `Req = ServerRequest`,
  `PeerReq = ClientRequest`.

This single generic abstraction makes the entire pump and `Peer` logic shared
between client and server, with the role parameter selecting message directions.

### 5.2 `Service` trait and handlers

`Service<R>` (`service.rs:132`) has three methods: `handle_request`,
`handle_notification`, `get_info`. The user never implements `Service` directly
for normal cases — instead:

- `ServerHandler` (`handler/server.rs`) has a default-method per server-handled
  request (`initialize`, `ping`, `complete`, `set_level`, `get_prompt`,
  `list_prompts`, `list_resources`, `list_resource_templates`, `read_resource`,
  `subscribe`, `unsubscribe`, `call_tool`, `list_tools`, `on_custom_request`,
  task methods `enqueue_task`/`list_tasks`/`get_task_info`/`get_task_result`/
  `cancel_task`, and `get_info`). A blanket `impl<H: ServerHandler> Service<RoleServer> for H`
  dispatches the incoming `ClientRequest` enum to the right method.
- `ClientHandler` (`handler/client.rs`) symmetrically handles the server→client
  requests (`ping`, `create_message`, `list_roots`, `create_elicitation`,
  `on_custom_request`) and all server notifications (`on_progress`,
  `on_logging_message`, `on_resource_updated`, etc.).

All handler methods have sensible defaults (e.g. unimplemented methods return
method-not-found), so a minimal server is `impl ServerHandler for Foo {}`.

### 5.3 `Peer<R>` (`service.rs:383`)

A cloneable handle to the remote side backed by an `mpsc` channel
(`PeerSinkMessage`). It exposes `send_request`, `send_notification`,
`send_request_with_option`, `send_cancellable_request`. Request IDs come from a
pluggable `RequestIdProvider` (default `AtomicU32Provider`), progress tokens from
`ProgressTokenProvider`. `RequestHandle` (`service.rs:311`) supports
`await_response` (with optional timeout that auto-sends a cancellation
notification) and `cancel(reason)`.

### 5.4 The message pump (`serve_inner`, `service.rs:742`)

- One sequential `receive` loop. Pending outbound requests tracked in
  `HashMap<RequestId, Responder>`; a parallel `HashMap<RequestId, CancellationToken>`
  (`local_ct_pool`, `service.rs:766`) supports cancelling in-flight inbound work.
- Each inbound request is processed in a spawned task: `spawn` is `tokio::spawn`
  normally, or `tokio::task::spawn_local` under the `local` feature
  (`service.rs:721-738`) — letting `!Send` handlers run on a `LocalSet`.
- Incoming `notifications/cancelled` triggers the matching token
  (`service.rs:920-933`). The whole connection is governed by a
  `tokio_util::sync::CancellationToken` with a `DropGuard` so dropping the
  `RunningService` tears the connection down cleanly.

### 5.5 `Send`/`!Send` strategy

Conditional supertraits `MaybeSend`/`MaybeSendFuture` and a `MaybeBoxFuture`
alias (`service.rs:16-43`) toggle the `Send + Sync` bounds based on the `local`
feature, supporting both multithreaded and single-threaded runtimes from one
codebase. `tower` integration lives in `service/tower.rs`.

---

## 6. Ergonomic Mechanisms (low-boilerplate API)

This is the heart of `rmcp`'s developer experience. **The capability** is
"register a tool/prompt with a name, schema, and handler"; **the Rust mechanism**
is attribute macros + type-driven schema derivation + routers.

### 6.1 `#[tool]` (proc macro, `rmcp-macros/src/tool.rs`)

Annotates an `async`/sync method as a tool handler. It generates a companion
function returning a `rmcp::model::Tool` (name, description, schemas, annotations).
Behaviors:

- **Name**: defaults to the function name; overridable with `name = "..."`.
- **Description**: defaults to the function's doc-comment (`extract_doc_line`),
  overridable.
- **Input schema**: auto-derived from the `Parameters<T>` argument's `T:
  JsonSchema`. No manual schema unless you pass `input_schema = ...`.
- **Output schema**: auto-derived when the return type is `Json<T>` or
  `Result<Json<T>, E>` (`extract_schema_from_return_type`, `tool.rs:26-77`).
- Supports `title`, `annotations(...)` (read_only/destructive/idempotent/open_world
  hints), `execution(task_support = "...")`, `icons`, `meta`, and `local`.

### 6.2 `#[tool_router]` / `#[tool_handler]`

- `#[tool_router]` on an `impl` block scans for `#[tool]` methods and generates a
  `tool_router()` function returning a `ToolRouter<Self>`. Routers compose with
  `+` (`Add`), enabling per-module routers (`vis`, `router` name options).
- `#[tool_handler]` on `impl ServerHandler for T {}` generates `call_tool`,
  `list_tools`, `get_tool`, and (unless you wrote one) `get_info()` with the tools
  capability enabled and server name/version read from `Cargo.toml`. Passing
  `#[tool_router(server_handler)]` even emits the `impl ServerHandler` block, so a
  whole tools server can be near-zero boilerplate.

### 6.3 Prompts: `#[prompt]`, `#[prompt_router]`, `#[prompt_handler]`

Mirror the tool macros (`rmcp-macros/src/prompt*.rs`). `#[prompt]` derives
`PromptArgument`s from a `Parameters<T>` signature; `#[prompt_handler]` generates
`get_prompt`/`list_prompts` + `get_info()` with the prompts capability.

### 6.4 `#[task_handler]`

Generates `enqueue_task`/`list_tasks` backed by a shared
`Arc<Mutex<OperationProcessor>>` (default `self.processor`), spawning task futures.
Requires the handler to be `Clone`.

### 6.5 Wrapper / extraction types

- `Parameters<P>(pub P)` (`handler/server/wrapper/parameters.rs`):
  `#[serde(transparent)]`, and forwards `JsonSchema` to `P`. This is the
  extractor that drives both runtime deserialization and compile-time schema
  derivation — analogous to axum extractors.
- `Json<T>` (`handler/server/wrapper/json.rs`): marks a return value as structured
  output; its `JsonSchema` impl feeds the tool's `output_schema`.
- Tool handlers may return many things via `IntoCallToolResult`/`IntoContents`
  (`String`, `Content`, `()`, `Json<T>`, `Result<..., E: Into<ErrorData>>`).

### 6.6 Routers (`handler/server/router/`)

`ToolRouter<S>` and `PromptRouter<S>` hold a `map` of name → boxed handler,
support `add_route`, `disable_route`/`enable_route` (emitting
`tools/list_changed` via a deferred peer-notifier, `router.rs:29`), `list_all`,
and `transparent_when_not_found` fallback to the underlying `ServerHandler`. The
combined `Router<S>` (`handler/server/router.rs:17`) wires both routers plus the
service and dispatches `CallTool`/`ListTools`/`GetPrompt`/`ListPrompts` itself,
forwarding the rest. There is also a non-macro path: implement `ToolBase` +
`SyncTool`/`AsyncTool` traits (`router/tool/tool_traits.rs`) and register with
`ToolRouter::new().with_sync_tool::<T>()` — recommended for larger codebases.

### 6.7 Tool-name validation (`handler/server/tool_name_validation.rs`)

Per the tool-name SEP: 1–128 chars, ASCII alnum + `_ - .`; emits warnings for
spaces, commas, leading/trailing dashes, etc.

### 6.8 JSON Schema derivation (`handler/server/common.rs`)

`schema_for_type::<T>()` uses `SchemaSettings::draft2020_12()` and is **cached**
by `TypeId`. It strips the OpenAPI-3 `format` extensions that aren't valid in JSON
Schema 2020-12 (`common.rs:26-30`). `schema_for_output::<T>()` requires the root
schema to be an object (rejects primitives), matching MCP's structured-output
rule. `schema_for_empty_input()` provides the no-arg case.

---

## 7. Error Handling (`error.rs`)

- **`ErrorData`** (defined in `model.rs:519`, re-exported from `error.rs`) is the
  wire-level JSON-RPC error: `{ code: ErrorCode, message: Cow<str>, data:
  Option<Value> }`. It implements `std::error::Error`. Constructor helpers map to
  named codes (`invalid_params`, `method_not_found::<M>()`, `internal_error`,
  `resource_not_found`, `parse_error`, `url_elicitation_required`).
- **`RmcpError`** (`error.rs:24`) is the unified runtime error enum (non-exhaustive,
  `thiserror`): variants `Service(ServiceError)`, `ClientInitialize`,
  `ServerInitialize`, `Runtime(JoinError)`, `TransportCreation{...}`,
  `TaskError(String)`.
- **`ServiceError`** (`service.rs:72`): `McpError`, `TransportSend`,
  `TransportClosed`, `UnexpectedResponse`, `Cancelled{reason}`, `Timeout{timeout}`.
- `Error` is a deprecated alias to `ErrorData`.
- **Propagation**: handler methods return `Result<_, ErrorData>`; tool handlers
  may return any `E: Into<ErrorData>`. The pump converts handler errors into
  `JsonRpcError` responses. Tool *execution* failures can also be reported
  in-band via `CallToolResult { is_error: Some(true), .. }` (`CallToolResult::error`,
  `model.rs:2842`) rather than a JSON-RPC error — the standard MCP distinction
  between protocol errors and tool errors.

---

## 8. Quality Infrastructure

### 8.1 Conformance (`conformance/`)

A binary harness (`conformance/src/bin`) plus committed result reports:

- `conformance/results/2026-02-25-rust-sdk-assessment.md`: a Tier audit. At that
  snapshot **server conformance 83.3% (25/30)**, **client 85.0% (17/20)**;
  overall **Tier 3** (held back by issue-triage SLA, label hygiene, lack of a
  ≥1.0.0 release at the time, sparse prose docs, and missing ROADMAP/VERSIONING).
- `conformance/results/2026-02-25-rust-sdk-remediation.md`: concrete Tier-2 and
  Tier-1 action lists.
- `ROADMAP.md` (now present) tracks SEP-1730 Tier 1: **server 87.5% (28/32),
  client 80.0% (16/20)**, listing the exact failing scenarios
  (`prompts-get-with-args`, `prompts-get-embedded-resource`,
  `elicitation-sep1330-enums`, `dns-rebinding-protection`; client auth scenarios).

### 8.2 Tests

~55 integration tests under `crates/rmcp/tests/` (declared with `required-features`
in `Cargo.toml:203-369`), covering: tool/prompt macros and routers, structured
output, JSON-schema detection, complex schema, sampling, elicitation, logging,
notifications, progress subscriber, tasks + task-support validation, custom
requests/headers, message protocol/schema, close/connection behavior, and a large
suite of streamable-HTTP scenarios (priming, JSON response, protocol version,
4xx body, stale/idle session, session store, connection reuse, concurrent SSE
streams), plus cross-language interop tests `test_with_python.rs` / `test_with_js.rs`.
Unit tests live inline in the model/capability/router files.

### 8.3 CHANGELOG / versioning

`crates/rmcp/CHANGELOG.md` follows Keep-a-Changelog + SemVer; current 1.7.0
(2026-05-13). 2025-11-25 protocol support landed in 1.5.0 (PR #802). Releases are
automated via `release-plz`.

### 8.4 CI (`.github/workflows/`)

`ci.yml`, `codeql.yml` (CodeQL security scan, config in `.github/codeql/`),
`release-plz.yml` (automated releases), `auto-label-pr.yml`, `triage.yml`.
`dependabot.yml` configures weekly Cargo + daily Actions updates.

### 8.5 Feature flags (`crates/rmcp/Cargo.toml:115-186`)

Fine-grained and additive. `default = ["base64", "macros", "server"]`. Notable:
`client`, `server`, `macros`, `elicitation`, `auth` / `auth-client-credentials-jwt`,
`schemars`, `tower`, `local` (single-threaded `!Send` mode), and a family of
`transport-*` flags (`transport-io`, `transport-child-process`,
`transport-streamable-http-client[-reqwest|-unix-socket]`,
`transport-streamable-http-server[-session]`, `transport-worker`,
`which-command`) plus reqwest TLS variants. Clippy lints `exhaustive_structs`/
`exhaustive_enums` are set to `warn`, forcing deliberate `#[non_exhaustive]` vs
`#[expect(...exhaustive...)]` decisions on every public type.

---

## 9. Targeted Spec Version

**`rmcp` targets MCP 2025-11-25 as the latest, while remaining
backward-compatible with three prior dated versions.** Evidence:

- `ProtocolVersion` constants (`model.rs:154-167`):
  `V_2025_11_25`, `V_2025_06_18`, `V_2025_03_26`, `V_2024_11_05`, with
  `LATEST = V_2025_11_25` (the default) and
  `KNOWN_VERSIONS = [2024-11-05, 2025-03-26, 2025-06-18, 2025-11-25]`.
  Deserialization recognizes all four and tolerates unknown strings (`model.rs:184-200`).
- `JsonRpcError.id` optionality cites "MCP 2025-11-25 §Error Responses"
  (`model.rs:464-466`).
- `Tool` task fields cite the 2025-11-25 tasks spec (`model/tool.rs:50`).
- CHANGELOG 1.5.0: "add 2025-11-25 protocol version support (#802)".
- Conformance results run scenarios tagged `2025-06-18` and `2025-11-25` (and
  `2025-03-26` for legacy OAuth back-compat).
- Numerous types reference SEP numbers being implemented: SEP-1319 (`_meta`/tasks),
  SEP-1577 (sampling tools, tool-use/result content), SEP-1724 (extensions),
  SEP-1730 (Tier 1 conformance), SEP-1330/1034 (elicitation enums/defaults).

---

## 10. Notes for Erlang Re-realization (capability vs. mechanism)

- **Typed method names**: `rmcp` uses zero-sized `const_string!` types so a method
  name is both data and a compile-time tag. In Erlang the natural equivalent is an
  atom plus binary literal; the validation logic (exact-match deser) would move
  into a decode function.
- **Type-state capability builder**: a Rust-specific trick (const-bool generics).
  In Erlang this collapses to a plain map/record with helper functions; the
  "method only available after enabling parent" guarantee becomes a runtime check.
- **Schema derivation**: `rmcp` leans entirely on `schemars` reflecting Rust types.
  Erlang has no equivalent reflection; schemas would be authored explicitly or
  generated from records via a custom mechanism. The MCP capability (a tool has an
  input JSON Schema 2020-12 object, output schema must be an object) is what
  carries over.
- **Role symmetry**: the `ServiceRole` abstraction (one pump, two role types) maps
  cleanly to an Erlang gen_server/process where direction is a parameter; the
  client/server split of which requests each side *handles* is pure protocol and
  transfers directly.
- **Routers + extractors** (`Parameters<T>`, `Json<T>`, `ToolRouter`) are the
  ergonomic core; the paradigm-neutral capability is "a registry mapping
  tool/prompt name → handler with associated schema and metadata, with runtime
  enable/disable emitting list_changed."
- **Concurrency**: per-request spawned tasks + a request-id→cancellation-token map
  is a clean model that an Erlang implementation already gets naturally from
  per-request processes; cancellation is `notifications/cancelled` keyed by request id.

---

*File produced for phase-1 planning; all paths are relative to
`/Users/oubiwann/lab/erlsci/erlmcp/workbench/rmcp` unless absolute.*
