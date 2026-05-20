# Phase 2 — The hypothetical idiomatic erlmcp

This is the design sketch of the erlmcp we *would* build if we started today with
(a) the full MCP capability set from `phase0-mcp-capability-rubric.md`, (b) the
house style from `phase0-erlang-rubric.md`, and (c) rmcp's proven feature surface
as the "what good looks like" reference — but realized in OTP, not transliterated
from Rust.

It is deliberately written before the gap analysis (Phase 3) so that the gap
analysis measures 0.5.0 against an *ideal*, not against Rust.

---

## 0. The translation rule

> **Imitate the protocol, not the language.**

rmcp is excellent, but a large fraction of what makes it excellent is Rust-specific
machinery (proc macros, `serde`/`schemars` derivation, `Result` threading, typed
`async` services). Copying that machinery into Erlang would be both impossible and
wrong. For each capability we ask two separate questions:

1. *What does the MCP spec require?* (paradigm-neutral — from Phase 0)
2. *What is the most idiomatic OTP mechanism that satisfies it?* (from the Erlang rubric)

Where the idiomatic OTP mechanism is **better** than rmcp's (cancellation,
concurrency, hot reconfiguration), we say so and lean in. Where it is **weaker**
(compile-time schema derivation), we say so honestly and mitigate.

---

## 1. The central ergonomics problem: defining a tool without macros

rmcp's signature move is `#[tool]`: the macro derives the tool name from the
function name, the description from the doc comment, and — crucially — the JSON
Schema from the parameter type via `schemars`. One annotated `impl` block yields a
complete, schema-validated tool server.

Erlang has no equivalent and, per the house style, **must not** invent one
(Inaka: "No Macros"; parse transforms are off the table). This is the hardest
ergonomic gap to close, so name it plainly:

> **Honest limitation:** erlmcp cannot auto-derive a tool's JSON Schema from
> Erlang types. There is no runtime type reflection rich enough, and the
> compile-time route (parse transform) violates the house style. Schema must be
> *stated*, not *derived*.

We close most of the gap three ways, none of which use macros:

**(a) A schema builder — plain functions, not hand-written JSON.** The boilerplate
rmcp eliminates isn't "having a schema", it's "writing the schema by hand as a
nested map". A composable builder recovers most of that ergonomics:

```erlang
Schema = erlmcp_schema:object([
    erlmcp_schema:field(<<"location">>, string, [required, {doc, <<"City name">>}]),
    erlmcp_schema:field(<<"units">>, {enum, [<<"c">>, <<"f">>]}, [{default, <<"c">>}])
]).
```

This is idiomatic (functions over data), Dialyzer-checkable, and far less
error-prone than literal JSON Schema maps. It also produces the schema *and* a
matching validator in one place.

**(b) Data-driven registration.** A tool is a value — a map with `name`,
`description`, `input_schema`, optional `output_schema`, and a `handler`:

```erlang
erlmcp:add_tool(Server, #{
    name        => <<"get_weather">>,
    description => <<"Look up current weather for a city">>,
    input_schema  => Schema,
    output_schema => erlmcp_schema:object([...]),   %% enables structured content
    handler     => fun weather:lookup/2
}).
```

`handler` is `fun((Args, Ctx) -> Result)` or `{Module, Function}`. This is the
0.5.0 spirit, kept, but with output schema and a richer `Ctx` (see §3).

**(c) A handler behaviour for larger servers.** When a server has many tools, a
callback module is cleaner than N registration calls. Per the rubric, extension
points are **behaviours with `-callback`**, not dynamic dispatch:

```erlang
-module(my_tools).
-behaviour(erlmcp_server_handler).
-export([tools/0, handle_tool/3]).

-spec tools() -> [erlmcp:tool_spec()].
tools() ->
    [#{name => <<"get_weather">>, description => <<"...">>,
       input_schema => weather_schema()}].

-spec handle_tool(binary(), map(), erlmcp:ctx()) -> erlmcp:tool_result().
handle_tool(<<"get_weather">>, #{<<"location">> := Loc}, _Ctx) ->
    {ok, erlmcp:text(weather:lookup(Loc))}.
```

The framework introspects `tools/0` once at registration to answer `tools/list`,
and routes `tools/call` to `handle_tool/3`. No `apply/3` guesswork — the behaviour
contract is `xref`-checkable (Inaka: "Avoid dynamic calls").

**Net:** erlmcp won't match rmcp's *derive-from-types* magic, but it can match the
*amount of code a user writes* fairly closely, while staying idiomatic. That's the
honest target.

---

## 2. Wire & model layer: opaque types, not shared records

rmcp models every MCP message as a typed Rust struct/enum with `serde`. The Erlang
rubric forbids the obvious analogue: **don't share records across modules, no
records in `.hrl`, no records in specs, no types in include files** (all Inaka).

So the model layer exposes **opaque types with constructor/accessor functions**:

```erlang
%% erlmcp_model.erl
-opaque request()  :: #{...}.   %% internal shape private to this module
-opaque response() :: #{...}.
-export_type([request/0, response/0, ...]).

-spec request_method(request()) -> binary().
-spec request_id(request()) -> id() | undefined.
-spec make_error(id(), error_code(), binary()) -> response().
```

Records may still be used *privately within a module* (e.g. session state), but
they never cross a module boundary and never appear in an exported spec.

JSON-RPC envelope handling lives in `erlmcp_json_rpc` (encode/decode/validate the
2.0 envelope, classify request/response/notification/batch, map error codes). The
JSON codec itself sits behind `erlmcp_codec` so the JSON library (currently `jsx`)
is swappable — and so the rest of the system never calls `jsx:` directly.

**Validation actually wired up.** The audit found `jesse` declared but never used.
In the ideal design, input args are validated against `input_schema` and tool
output against `output_schema` at the session boundary *before* dispatch / *before*
sending — turning the advertised "JSON Schema validation" into a real guarantee
(Quality axis B; rubric: "validate at the API edge").

---

## 3. Concurrency & lifecycle — the headline divergence

This is where Erlang should stop imitating Rust and start winning.

rmcp runs a single async message pump (a tokio task) with a shared
`request-id → CancellationToken` map and spawns a task per request. That is Rust
reconstructing, by hand, what the BEAM gives for free.

**The idiomatic OTP shape:**

```
                erlmcp_sup (one_for_one)
                 ├── erlmcp_registry        (gen_server: discovery only, see §4)
                 ├── erlmcp_session_sup     (simple_one_for_one)
                 │     └── erlmcp_server_session (gen_statem)   <- one per connection
                 │            └── (spawns) request_worker        <- one per in-flight request
                 └── erlmcp_transport_sup   (one_for_one)
                       └── erlmcp_transport_* (gen_server impl of erlmcp_transport)
```

**Session = `gen_statem`.** The lifecycle (`uninitialized → initializing →
operational → shutting_down`) is a genuine state machine; capability/version
negotiation gates which methods are legal. The rubric explicitly prefers
`gen_statem` for protocol/handshake state machines and `gen_server` for plain
request/reply. The session owns the transport connection and the in-flight
request table.

**One process per in-flight request.** A slow or blocking tool handler must not
head-of-line-block the session, and the session must not crash if a handler
throws. So each request is run in a short-lived worker process the session
monitors. This gives us, for free:

- **Cancellation = process termination.** `notifications/cancelled` → the session
  kills the worker. No `CancellationToken`, no cooperative cancellation checks,
  no map to maintain. The BEAM *is* the cancellation primitive. This is strictly
  simpler and more reliable than rmcp's hand-rolled token plumbing.
- **Timeouts** are a worker monitor timeout, not a `select!` race.
- **Isolation:** a handler that crashes produces an `'EXIT'` the session catches
  and converts into a JSON-RPC `-32603` error response (see §5). One bad tool call
  cannot take down the session.

**Server→client requests** (sampling, elicitation, roots, ping) are issued *from
inside a request worker* through the session, which correlates the reply. Because
each worker is its own process, a tool can synchronously "ask the client to sample
an LLM completion" by blocking on a `gen_statem:call`-style round-trip without
blocking anything else. In rmcp this requires careful async re-entrancy; here it's
just a process waiting on a message.

**Progress** is `Ctx`-mediated: a worker calls `erlmcp_ctx:report_progress(Ctx,
Fraction, Msg)`, which sends a `notifications/progress` through the session keyed
by the request's `progressToken`.

**Tasks (long-running work)** map perfectly: a task is a supervised process under
a task supervisor; `tasks/get` / `tasks/result` / `tasks/cancel` query or signal
it; `tasks/list` enumerates the children. This is a near-trivial feature in Erlang
that is comparatively fiddly in an async runtime.

---

## 4. The registry: discovery, not a message bus

0.5.0 routes *every message* through a central `erlmcp_registry` gen_server. That's
a latent bottleneck and single point of failure, and it couples transports to
servers through a third party for no protocol reason.

In the ideal design the registry does **discovery and binding only**: "transport
`T` is bound to server-definition `S`". Once a connection is established, the
session process talks to its transport and handler set **directly** — no per-message
hop through the registry. (If multi-node or named lookup is wanted, `pg`/`gproc`
are the idiomatic tools; a bespoke registry gen_server on the hot path is not.)

A "server" in this model is a *definition* (a named capability set + handler
modules/funs). Each inbound connection spawns a session bound to that definition.
This cleanly supports both the 1:1 stdio case and the many-clients HTTP/SSE case.

---

## 5. Error handling — let it crash, but translate at the boundary

The rubric's guidance ("validate at the edge, let it crash internally,
supervision is the error strategy") resolves a tension MCP creates: the protocol
*requires* well-formed error responses, but Erlang *wants* to crash on the
unexpected.

The resolution is a clear boundary:

- **Inside a request worker:** let it crash. No defensive `try` around business
  logic, no error tuples threaded through helpers.
- **At the session↔worker boundary:** the session monitors the worker. A normal
  return becomes a JSON-RPC result; a handler-returned `{error, Code, Msg}` becomes
  a JSON-RPC error; an *abnormal* exit becomes `-32603 internal error` (with the
  crash logged). The client always gets a spec-compliant response; the server
  stays up.
- **At the public API edge** (client-side calls like `erlmcp:add_tool/2`):
  defensive validation with clear `{error, Reason}` returns, because the caller is
  a programmer who deserves a good message, not a crash.

So `{ok, _} | {error, _}` lives at the *edges* (handler results, public API), and
let-it-crash governs the *interior*. We do **not** thread `Result`-style errors
through the supervision tree the way Rust threads `Result<T,E>` everywhere.

---

## 6. Transports — one behaviour, several implementations

Define `erlmcp_transport` as a behaviour with `-callback`s (rubric: extension
points are behaviours; encapsulate OTP calls behind API functions). This interface
is **harvested from the July-2025 prior art** (`phase5-prior-art-reconciliation.md`),
which had already designed it well — adopted with one adaptation (see below):

```erlang
%% Core transport behaviour
-callback init(TransportId :: atom(), Config :: map()) ->
    {ok, state()} | {error, term()}.
-callback send(state(), iodata()) -> ok | {error, term()}.
-callback close(state()) -> ok.

%% Optional, for richer transports
-callback get_info(state()) -> #{type => atom(), status => atom(), peer => term()}.
-callback handle_transport_call(Request :: term(), state()) ->
    {reply, term(), state()} | {error, term()}.
-optional_callbacks([get_info/1, handle_transport_call/2]).

%% Standard inbound message vocabulary a transport emits
-type transport_message() ::
      {transport_data, binary()}
    | {transport_connected, map()}
    | {transport_disconnected, term()}
    | {transport_error, atom(), term()}.
```

Each transport is a `gen_server` implementing the behaviour: `erlmcp_transport_stdio`,
`_tcp`, `_http` (SSE), and `_streamable_http` (the current spec's HTTP transport).
Map-based config is validated per-type by a harvested `validate_transport_config/1`
(the stdio/tcp/http required+optional field sets are already specified in the prior
art and can be adopted near-verbatim).

**The one adaptation from the prior art:** the July design had each transport deliver
inbound data *to the registry* (`erlmcp_registry:route_to_server/3`) and receive
outbound data *from the registry*. Here the transport instead delivers inbound data
**directly to its bound session process** and receives outbound data from it — the
registry is consulted once at bind time, then stays off the message path (§4; the
registry decision is flagged in `phase5-prior-art-reconciliation.md` §4.1). The
behaviour signatures are unchanged; only the message destination differs.

The session is fully transport-agnostic. This directly fixes three audit findings:
the `gen_server:call(self(), ...)` deadlock bug, the inconsistent transport
implementations, and the supervisor's references to nonexistent `*_tcp_new` /
`*_http_new` modules. Strings/framing use iolists, not concatenation (Inaka).

---

## 7. Client side — symmetric, with callback behaviours

The client is the mirror image: `erlmcp_client_session` (gen_statem) drives
`initialize`, then exposes `list_tools`, `call_tool`, `read_resource`,
`get_prompt`, etc. as API functions that block on a correlated round-trip.

The protocol's server→client features become **client callback behaviours** the
embedder implements:

```erlang
-behaviour(erlmcp_sampling).      %% handle_create_message/2  -> LLM completion
-behaviour(erlmcp_roots).         %% list_roots/1
-behaviour(erlmcp_elicitation).   %% handle_elicit/2          -> user input
```

This is the idiomatic inversion of rmcp's `ClientHandler` trait. OAuth 2.1 (which
rmcp supports for HTTP clients) is a large, self-contained subsystem and is
sequenced late in Phase 4, not part of the core.

---

## 8. Capabilities & negotiation

A small `erlmcp_capabilities` module builds and negotiates the capability/version
maps. Capabilities are *data* (a map advertised in `initialize`), derived from what
the server definition actually registered (if no prompts are registered, don't
advertise `prompts`). Version negotiation picks the highest mutually supported
protocol version from a declared set — a first-class feature, not a constant.

---

## 9. Conformance & testing as a deliverable

rmcp's most enviable quality artifact is its **conformance harness with dated
scorecards**. The ideal erlmcp ships `erlmcp_conformance`: a Common Test suite that
drives a real session through every L0–L4 capability and emits a versioned
scorecard, plus interop tests against a reference server/client. Layered testing
per the rubric:

- **EUnit** for pure units (schema builder, JSON-RPC envelope, model accessors),
  1–2 assertions each.
- **Common Test** for session lifecycle, transports, end-to-end flows.
- **PropEr** for the protocol state machine and envelope round-tripping — exactly
  the kind of stateful/fuzzable surface property testing exists for.

Coverage gate moves off `--min_coverage=0` to a real threshold.

---

## 10. Proposed module map (the shape of 0.6.0)

| Module | Behaviour | Role |
|---|---|---|
| `erlmcp` | — | public facade / API (the one curated module) |
| `erlmcp_app` | application | OTP app |
| `erlmcp_sup` | supervisor | top supervisor |
| `erlmcp_session_sup` | supervisor (s_o_f_o) | spawns sessions |
| `erlmcp_transport_sup` | supervisor | spawns transports |
| `erlmcp_server_session` | gen_statem | server-side protocol state machine |
| `erlmcp_client_session` | gen_statem | client-side protocol state machine |
| `erlmcp_registry` | gen_server | discovery/binding only (off the hot path) |
| `erlmcp_json_rpc` | — | JSON-RPC 2.0 envelope encode/decode/classify |
| `erlmcp_codec` | — | JSON library wrapper (swappable) |
| `erlmcp_model` | — | opaque MCP types + constructors/accessors |
| `erlmcp_schema` | — | JSON Schema builder + validator |
| `erlmcp_capabilities` | — | capability + version negotiation |
| `erlmcp_ctx` | — | request context: progress, cancellation, _meta, peer calls |
| `erlmcp_server_handler` | behaviour | user tool/resource/prompt handler contract |
| `erlmcp_transport` | behaviour | transport contract |
| `erlmcp_transport_stdio` | gen_server + erlmcp_transport | stdio |
| `erlmcp_transport_tcp` | gen_server + erlmcp_transport | TCP |
| `erlmcp_transport_http` | gen_server + erlmcp_transport | HTTP+SSE |
| `erlmcp_transport_streamable_http` | gen_server + erlmcp_transport | streamable HTTP |
| `erlmcp_sampling` / `erlmcp_roots` / `erlmcp_elicitation` | behaviours | client-side server→client callbacks |
| `erlmcp_task_sup` / `erlmcp_task` | supervisor / proc | long-running tasks |
| `erlmcp_conformance` | — (CT) | conformance scorecard harness |

The three overlapping server implementations and all `_new` forks collapse into the
single `erlmcp_server_session` design.

---

## 11. Divergence ledger — rmcp mechanism → erlmcp realization

| rmcp (Rust) mechanism | erlmcp (OTP) realization | Why diverge |
|---|---|---|
| `#[tool]` proc-macro derives name/schema/dispatch | `erlmcp_schema` builder + data-driven `add_tool` + `erlmcp_server_handler` behaviour | No macros (house style); no type→schema reflection in Erlang. State the schema, don't derive it. |
| `schemars` derives JSON Schema from types | hand-stated schema via builder functions | Honest limitation; mitigated, not matched. |
| `serde` typed structs/enums for wire | `erlmcp_model` opaque types + accessors; maps on the wire | Don't share records/no records in specs; dynamic JSON ↔ maps is natural. |
| single async pump + `CancellationToken` map + spawned tasks | `gen_statem` session + one monitored process per request | The BEAM gives concurrency/isolation natively; **better**, not just equivalent. |
| cooperative cancellation via token | **cancellation = kill the worker process** | Strictly simpler and more reliable on the BEAM. |
| `Result<T,E>` threaded through service | let-it-crash inside; `{ok,_}|{error,_}` only at edges; session translates exits → JSON-RPC errors | Supervision is the error strategy (rubric). |
| central message routing | session talks to transport/handlers directly; registry = discovery only | Avoid a hot-path SPOF/bottleneck. |
| `ClientHandler` trait | `erlmcp_sampling`/`erlmcp_roots`/`erlmcp_elicitation` behaviours | `-callback` behaviours are the idiomatic extension point. |
| tower layers / middleware | OTP supervision + per-request processes | Cross-cutting concerns are processes, not layers. |
| feature flags (`client`/`server`/`local`) | OTP app + optional behaviours; roles are just which session you start | No conditional compilation culture in Erlang. |
| async tasks for long-running work | supervised task processes + `tasks/*` | Processes are the natural task primitive — **better fit**. |

---

## 12. Where erlmcp can be *better* than rmcp (not just at parity)

Worth stating, because "match rmcp" undersells the BEAM in three places:

1. **Cancellation & timeouts** — a process exit vs. hand-maintained tokens.
2. **Fault isolation** — one tool crash can't corrupt or kill a session; rmcp must
   be careful with panics across the async boundary.
3. **Long-running tasks & hot reconfiguration** — supervised task processes, and
   runtime add/remove of tools with automatic `list_changed`, are trivial here.

These should be framed as erlmcp's *selling points*, not apologies for not being
Rust.
