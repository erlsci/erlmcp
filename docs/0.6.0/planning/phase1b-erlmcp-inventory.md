# erlmcp 0.5.0 — Factual Inventory (Phase 1b baseline)

Source tree: `/Users/oubiwann/lab/erlsci/erlmcp`
App version (from `src/erlmcp.app.src`): **0.5.0**
MCP protocol version targeted (from `include/erlmcp.hrl:3`): **2025-06-18**
JSON-RPC version: **2.0**
This code was AI-generated (Sept 2025) without an Erlang style guide or expert review; observations below treat its idioms with appropriate skepticism. Nothing was modified.

---

## 1. Module Map & Supervision Tree

### Module table (src/ only)

| Module | Behavior | Role | Used? |
|---|---|---|---|
| `erlmcp` | none (facade) | Public top-level API: start/stop servers & transports, add resource/tool/prompt, config, convenience setups, legacy stdio. | Yes — primary entry point. |
| `erlmcp_app` | `application` | App callback; starts `erlmcp_sup`. | Yes. |
| `erlmcp_sup` | `supervisor` | Root supervisor, `one_for_all`. Starts registry + server_sup + transport_sup. Also exposes pass-through server/transport/stdio management API. | Yes. |
| `erlmcp_server_sup` | `supervisor` | `simple_one_for_one` for dynamic server instances. Starts **`erlmcp_server_new`** (not `erlmcp_server`). | Yes. |
| `erlmcp_transport_sup` | `supervisor` | `one_for_one` for dynamic transports. Dispatches by type to `erlmcp_transport_stdio_new` / `erlmcp_transport_tcp_new` / `erlmcp_transport_http_new`. | Yes (stdio path only). |
| `erlmcp_registry` | `gen_server` | Central registry & message router. Tracks servers, transports, server↔transport bindings, monitors. Routes `{mcp_message,...}` and `{mcp_response,...}`. | Yes — core of "new" architecture. |
| `erlmcp_server` | `gen_server` | Original full-featured MCP server (resources, templates, tools, prompts, subscribe/unsubscribe, progress). Registry-routed. | **Partially** — has the most features but is NOT the module started by `erlmcp_server_sup`. Reachable via `erlmcp_server:start_link/2` directly (e.g. `erlmcp.erl:483` fallback path). |
| `erlmcp_server_new` | `gen_server` | Trimmed re-implementation of `erlmcp_server`. Started by `erlmcp_server_sup`. | Yes — the actually-supervised server. |
| `erlmcp_client` | `gen_server` | MCP client: initialize, list/read/call, subscriptions, batching, notification & sampling handlers, strict mode. | Yes (standalone; not in supervision tree). |
| `erlmcp_json_rpc` | none (lib) | JSON-RPC 2.0 encode/decode over records, via `jsx`. | Yes. |
| `erlmcp_transport` | behavior def | Defines transport behavior: `init/1`, `send/2`, `close/1` (close optional). | Defined; inconsistently implemented (see §5). |
| `erlmcp_transport_stdio` | `gen_server` | Original stdio transport; sends `{transport_message, Line}` to an owner pid. | Used by `erlmcp_client` (`init_transport({stdio,...})`). |
| `erlmcp_transport_stdio_new` | `gen_server` | Registry-aware stdio transport; routes stdin to server via `erlmcp_registry:route_to_server/3`, writes `{mcp_response,...}` to stdout. | Yes — started by `erlmcp_transport_sup`/`erlmcp.erl`. |
| `erlmcp_transport_tcp` | `gen_server` | TCP transport with reconnect/backoff. Owner-pid model (`{transport_message,...}`). | Referenced by `erlmcp_client` (`{tcp, Opts}`); NOT wired into transport_sup. |
| `erlmcp_transport_http` | `gen_server` | HTTP transport via `httpc`, async, retry/backoff, pooling. | Referenced by `erlmcp_client` (`{http, Opts}`); NOT wired into transport_sup. |
| `erlmcp_stdio` | none (facade) | Thin facade over `erlmcp_stdio_server` (start/stop, add_tool/resource/prompt). | Yes (legacy stdio quick-start path). |
| `erlmcp_stdio_server` | `gen_server` | Self-contained legacy stdio MCP server with its own JSON-RPC handling and stdin reader. Does **not** use the registry or `erlmcp_server*`. | Yes (legacy fallback; registered locally as `erlmcp_stdio_server`). |

### Supervision tree (as actually wired)

```
erlmcp_app
 └── erlmcp_sup            (one_for_all, intensity 3 / 60s)
      ├── erlmcp_registry        (gen_server, permanent)
      ├── erlmcp_server_sup      (simple_one_for_one) → erlmcp_server_new (temporary)
      └── erlmcp_transport_sup   (one_for_one) → erlmcp_transport_*_new (temporary)
```

- `erlmcp_client` is **not** under any supervisor; callers start it directly with `erlmcp_client:start_link/1,2`.
- `erlmcp_stdio_server` is started ad-hoc (legacy path), registered locally, also not part of the declared tree's child specs.

### Started/registered processes (`erlmcp.app.src:4-8`)

`registered` lists: `erlmcp_sup`, **`erlmcp_client_sup`**, `erlmcp_server_sup`.
- `erlmcp_transport_sup` and `erlmcp_registry` are registered at runtime but **absent** from the `registered` list.
- **`erlmcp_client_sup` is declared in `registered` but there is no `erlmcp_client_sup` module in `src/`, and `erlmcp_sup` never starts it.** It is a phantom (referenced only in app.src and docs/architecture.md).

---

## 2. Public API

### `erlmcp` (top-level facade)

App/transport management:
- `start_server/1,2` :: `(server_id()[, map()]) -> {ok, pid()} | {error, term()}`
- `stop_server/1`, `list_servers/0`
- `start_transport/2,3` :: `(transport_id(), transport_type()[, map()])`. Only `stdio` implemented; `tcp`/`http` return `{error, {transport_not_implemented, _}}` (`erlmcp.erl:143-146`).
- `stop_transport/1`, `list_transports/0`
- `bind_transport_to_server/2`, `unbind_transport/1`

Server component registration (delegates to a found server pid):
- `add_resource/3,4`, `add_tool/3,4`, `add_prompt/3,4` (the `/4` variants read `template`/`schema`/`arguments` from an options map).

Config: `get_server_config/1`, `update_server_config/2`, `get_transport_config/1`, `update_transport_config/2`.

Legacy/convenience: `start_stdio_server/0,1`, `stop_stdio_server/0`, `start_stdio_setup/2`, `start_tcp_setup/3`, `setup_server_components/2`, `quick_stdio_server/3`.

### `erlmcp_server` (full-featured, original) — exports

`start_link/2`, `add_resource/3`, `add_resource_template/4`, `add_tool/3`, `add_tool_with_schema/4`, `add_prompt/3`, `add_prompt_with_args/4`, `subscribe_resource/3`, `unsubscribe_resource/2`, `report_progress/4`, `notify_resource_updated/3`, `notify_resources_changed/1`, `stop/1`.

Key signatures:
- `add_tool_with_schema(Server, Name :: binary(), Handler :: fun((map())->...), Schema :: map()) -> ok`
- `add_prompt_with_args(Server, Name, Handler, [#mcp_prompt_argument{}]) -> ok`
- `report_progress(Server, Token :: binary()|integer(), Progress :: float(), Total :: float()) -> ok`

### `erlmcp_server_new` (supervised) — exports

Same as above **minus** `subscribe_resource/3`, `unsubscribe_resource/2`, and `report_progress/4`. (`start_link/2`, `add_resource/3`, `add_resource_template/4`, `add_tool/3`, `add_tool_with_schema/4`, `add_prompt/3`, `add_prompt_with_args/4`, `notify_resource_updated/3`, `notify_resources_changed/1`, `stop/1`.)

### `erlmcp_client` — exports

`start_link/1,2`, `initialize/2,3`, `list_roots/1`, `list_resources/1`, `list_resource_templates/1`, `read_resource/2`, `subscribe_to_resource/2`, `unsubscribe_from_resource/2`, `list_prompts/1`, `get_prompt/2,3`, `list_tools/1`, `call_tool/3`, `with_batch/2`, `send_batch_request/4`, `set_notification_handler/3`, `remove_notification_handler/2`, `set_sampling_handler/2`, `remove_sampling_handler/1`, `set_strict_mode/2`, `stop/1`.

### `erlmcp_stdio` / `erlmcp_stdio_server` (legacy)

`erlmcp_stdio`: `start/0,1`, `stop/0`, `add_tool/3,4`, `add_resource/3,4`, `add_prompt/3,4`, `is_running/0`.
`erlmcp_stdio_server`: `start_link/1`, `add_tool/3,4`, `add_resource/3,4`, `add_prompt/3,4`, `stop/0`. Note its handler/arg shapes differ from `erlmcp_server` (`(Name, Description, Handler[, Schema/MimeType/Arguments])`).

---

## 3. MCP Feature Coverage

| Feature | Client | Server (`erlmcp_server`) | Server (`erlmcp_server_new`, supervised) | Notes |
|---|---|---|---|---|
| initialize / capability negotiation | Yes (sends, parses caps) | Yes | Yes | Protocol version hard-coded `2025-06-18`. |
| tools list/call | Yes | Yes | Yes | |
| resources list/read | Yes | Yes | Yes | |
| resource templates | list only (client `list_resource_templates`) | list + read-via-template add | **No** `resources/templates/list` handler | `erlmcp_server_new` drops templates list. |
| prompts list/get | Yes | Yes | Yes | |
| subscriptions (resources/subscribe,unsubscribe) | Yes (client tracks) | Yes (handlers + API) | **No** subscribe/unsubscribe handlers | |
| progress notifications | n/a | Yes (`report_progress/4`) | **No** | |
| resources updated / list_changed notifications | handled (client side) | Yes (emitted) | partial (updated + list_changed cast) | server uses `route_to_transport(broadcast, ...)` placeholder. |
| sampling (`sampling/createMessage`) | partial (handler dispatch only) | No | No | Server never issues sampling requests. |
| roots | `list_roots/1` exists but no handler in either server | No | No | Client call would hit `unknown_request`. |
| elicitation | No | No | No | Not present anywhere. |
| completion | No | No | No | Not present. |
| logging | capability advertised | advertised in caps only | advertised only | No `logging/setLevel` or log message methods. |
| pagination (cursor) | No | No | No | All `*/list` return full lists. |
| cancellation | No | No | No | No `notifications/cancelled`. |
| ping | No | No | No | |
| notifications/initialized | constant defined (`MCP_METHOD_INITIALIZED`) | not handled distinctly | not handled | Generic notification handler is a no-op. |
| batching | Yes (`with_batch/2`) | n/a | n/a | Client-only; sends sequentially, not a JSON-RPC batch array. |

---

## 4. Protocol / JSON-RPC Layer (`erlmcp_json_rpc.erl`)

- **JSON library: `jsx` 3.1.0.** Decode via `jsx:decode(Json, [return_maps])`, encode via `jsx:encode/1`.
- **JSON Schema validation: NOT IMPLEMENTED.** `jesse` 1.8.1 is declared as a dependency (`rebar.config:12`, `erlmcp.app.src:17`) but **never referenced in `src/`** (grep finds it only in app.src). Tool `inputSchema` is stored and echoed but not validated.
- **Message representation: records** (`include/erlmcp.hrl`): `#json_rpc_request{}`, `#json_rpc_response{}`, `#json_rpc_notification{}`. MCP domain objects are also records (`#mcp_tool{}`, `#mcp_resource{}`, `#mcp_prompt{}`, `#mcp_server_capabilities{}`, `#mcp_capability{}`, `#mcp_error{}`, etc.). Wire params/results are plain maps with binary keys defined as `?MCP_PARAM_*` / `?JSONRPC_FIELD_*` macros.
- Encode helpers: `encode_request/3`, `encode_response/2`, `encode_error_response/3`, `encode_notification/2`; decode: `decode_message/1`; `create_error/3` builds `#mcp_error{}`.
- Decoding is lenient (`decode_id/1`, `validate_params/1` coerce odd inputs). Version is validated against `<<"2.0">>`.
- **No JSON-RPC batch array support** in decode/encode (the client's "batch" is sequential single requests).
- **Initialization / capability negotiation:** server builds the `initialize` response in `build_initialize_response/1` (`erlmcp_server.erl:406`, dup in `erlmcp_server_new.erl:299`) reading version from `application:get_key`. `encode_server_capabilities/1` advertises resources (subscribe+listChanged), tools, prompts (listChanged), logging. Client `extract_server_capabilities/1` parses the response back into `#mcp_server_capabilities{}` (only resources/tools/prompts/logging recognized).

---

## 5. Transports

Behavior (`erlmcp_transport.erl`): `init/1`, `send/2`, `close/1` (close optional). **The abstraction is applied inconsistently:**

| Transport | start_link | send | close | init/1 callback? | Owner/routing model | Wired into transport_sup? |
|---|---|---|---|---|---|---|
| `erlmcp_transport_stdio` | `start_link/1` (owner pid) | `send/2` writes stdout directly (ignores state) | `close/1` | No (gen_server `init/1` only) | sends `{transport_message,Line}` to owner | No — used by `erlmcp_client` |
| `erlmcp_transport_stdio_new` | `start_link/2` (id, config) | `send/2` is a `gen_server:cast` | `close/1` | No | registry routing (`route_to_server`, `{mcp_response,...}`) | **Yes** (stdio) |
| `erlmcp_transport_tcp` | `start_link/1` (opts map) | `send/2` (pid or state map) | `close/1` | No transport `init/1`; has `connect/2` | owner pid `{transport_message,...}`; reconnect w/ exp backoff | No (sup expects `erlmcp_transport_tcp_new`) |
| `erlmcp_transport_http` | `start_link/1` (opts map) | `send/2` does `gen_server:call(self(), ...)` (suspicious self-call) | `close/1` no-op | has standalone `init([Opts])` shape | owner pid `{transport_message,...}`; httpc async + retry | No (sup expects `erlmcp_transport_http_new`) |

Supported transports in practice:
- **stdio**: two implementations (`erlmcp_transport_stdio` for client; `erlmcp_transport_stdio_new` for the registry server path). Working.
- **tcp / http**: modules exist and are fairly elaborate, usable directly by `erlmcp_client`, but **the registry-based server path cannot start them** — `erlmcp.erl:143-146` returns `transport_not_implemented` for tcp/http, and `erlmcp_transport_sup:start_child/3` (`erlmcp_transport_sup.erl:18-22`) maps tcp→`erlmcp_transport_tcp_new` and http→`erlmcp_transport_http_new`, **neither of which exists** (would crash with `undef`/case clause if reached).

`rebar.config:159-163` adds `xref_ignores` for `erlmcp_transport_stdio:read_loop/2` and `erlmcp_transport_tcp:send/2`, hinting these don't match the behavior cleanly.

---

## 6. The "_new" Duplication

### `erlmcp_server` vs `erlmcp_server_new`
- Both are `gen_server`, near-identical state record and `handle_call` clauses for adding resources/tools/prompts, both handle `{mcp_message,...}` from the registry, both build the same initialize response.
- **`erlmcp_server` is the superset.** It additionally implements: `subscribe_resource/3`, `unsubscribe_resource/2`, `report_progress/4`; the `resources/templates/list`, `resources/subscribe`, `resources/unsubscribe` request handlers; subscription bookkeeping; progress tokens; and "safe" wrappers (`send_*_safe`) that try/catch around registry sends.
- **`erlmcp_server_new` is the trimmed version**: no subscriptions, no progress, no templates-list/subscribe/unsubscribe handlers; sends directly (no safe wrappers); slightly richer `encode_resource` (emits description/metadata) and `encode_prompt_argument`.
- **Wiring: `erlmcp_server_sup` starts `erlmcp_server_new`** (`erlmcp_server_sup.erl:23,27,47,51`). So the *less* capable module is the one under supervision. `erlmcp_server` is only reached via the direct-`start_link` fallback in `erlmcp.erl:483` when `erlmcp_server_sup` is absent, and is the module the tests exercise (`test/erlmcp_server_tests.erl`).

### `erlmcp_transport_stdio` vs `erlmcp_transport_stdio_new`
- `erlmcp_transport_stdio` (original): owner-pid model, `start_link/1`, `send/2` writes to stdout directly, used by `erlmcp_client`.
- `erlmcp_transport_stdio_new`: registry model, `start_link/2`, `send/2` is a cast, routes via `erlmcp_registry`, handles `{mcp_response,...}`. This is the one the supervisor/`erlmcp.erl` uses.

### Verdict
This is an **abandoned / half-finished refactor** ("Phase 2" registry-based architecture, per comments in `erlmcp.erl` and `erlmcp_server.erl:127` "(refactored)"). The codebase is mid-migration:
- The supervised path uses the `_new` server (feature-reduced) and `_new` stdio transport.
- The original `erlmcp_server` retains the full feature set and the tests, but is off the supervised path.
- `_new` siblings for tcp/http were referenced by the new transport supervisor but **never created**, leaving tcp/http unusable through the registry architecture.
- A third, older, fully independent stdio implementation (`erlmcp_stdio_server`) coexists as the "legacy" fallback.
Net: three overlapping server implementations and two stdio transports, with the most-capable code paths not the ones actually supervised.

---

## 7. Error Handling & Types

- **`-spec` coverage is broad** across `src/` (most exported and internal functions have specs). `-type`/`-record` definitions centralized in `include/erlmcp.hrl` plus per-module `-type state()`.
- **Dialyzer**: heavily configured (`rebar.config:128-149`) with many warnings enabled (`unmatched_returns`, `error_handling`, `unknown`, etc.). Note many handlers `-spec` `handle_call` as returning only `{reply, term(), state()}` while some clauses actually return `{noreply,...}` or `{stop,...}` (e.g. `erlmcp_server.erl:130-131` vs clauses at 295/305; `erlmcp_client.erl:198-201` does declare the union) — likely dialyzer-relevant inaccuracies.
- **Protocol error codes**: defined as macros in `erlmcp.hrl` — standard JSON-RPC (-32700..-32603) plus MCP server-range codes (-32001..-32010) with matching message macros. `#mcp_error{}` record carries code/message/data.
- **Error model**: mostly **error-tuples** (`{ok,_}` / `{error,_}`) at API boundaries, with **let-it-crash** inside handlers wrapped by `try/catch` that converts handler crashes into JSON-RPC `INTERNAL_ERROR` responses (`erlmcp_server.erl:474-485`, `488-502`, `505-521`). Registry/transport use `process_flag(trap_exit, true)` + `monitor/2` for cleanup. Some defensive `catch` of registry calls (`send_*_safe`).
- Exceptions surface as `{error, {Class, Exception}}` in places (`erlmcp.erl:450-451`).

---

## 8. Tests

Test code lives in **two locations** (unusual):
- `test/` — eunit suites: `erlmcp_json_rpc_tests`, `erlmcp_server_tests`, `erlmcp_registry_tests`, `erlmcp_advanced_tests`, `erlmcp_client_advanced_tests`.
- `priv/test/` — eunit suites: `erlmcp_stdio_tests`, `json_parsing_tests`, `stdio_server_tests`. These are only compiled under the `testlocal` profile (`rebar.config:51-52` adds `priv/test` to `src_dirs`); the standard `test` profile/CI does **not** include `priv/test`.

Test framework:
- **EUnit only in practice.** Every suite uses `-include_lib("eunit/include/eunit.hrl")`. `test/erlmcp_server_tests.erl` is the largest (~76 `?_test`/test functions referenced).
- **Property-based**: `proper` is declared as a test dep and `rebar3_proper` plugin is configured (`rebar.config:35,178`, aliases `check`/`test` run proper), but **no `*_prop` / proper-style modules exist** in the tree — proper is wired but unused.
- **Common Test**: `Makefile` `test` target runs `ct`, but **no `*_SUITE.erl` files exist**. So `ct` is a no-op/likely error.
- **Conformance suite**: none. No MCP conformance harness.

CI: `.github/workflows/ci.yml` exists. Runs on OTP **25, 26, 27, 28** (ubuntu-22.04). Steps: `rebar3 compile`, `rebar3 xref`, `rebar3 eunit -v`, `rebar3 as test cover -v --min_coverage=0`. **Coverage gate is `--min_coverage=0`** (i.e. no real minimum). No dialyzer, ct, or proper in CI despite Makefile/rebar config supporting them. Coveralls is configured in rebar.config but not invoked by the workflow.

Coverage focus: JSON-RPC encode/decode, the original `erlmcp_server` add/list flows, registry register/find/bind, some client advanced behavior, and (testlocal-only) legacy stdio. The supervised `erlmcp_server_new` and the tcp/http transports appear largely untested.

---

## 9. Docs & Build

### Docs (`docs/`)
- `architecture.md`, `api-reference.md`, `otp-patterns.md`, `protocol.md`.
- **`docs/architecture.md` is stale**: it diagrams `erlmcp_client_sup` and a `erlmcp_sup → client_sup/server_sup` tree that does not match the actual registry-based tree, and lists transports without the `_new` split. No root `README.md` exists (though `erlmcp.app.src:47` lists `README.md` in `files`). Per-example READMEs exist under `examples/*/`.
- Release notes under `priv/release-notes/` go 0.2.0 → 0.3.1 (no 0.4/0.5 notes).

### Build / config
- `rebar.config`: deps `jsx 3.1.0`, `jesse 1.8.1`. Profiles: `prod` (warnings_as_errors), `test` (proper/meck/coveralls, cover), `testlocal` (adds priv/test + examples to src_dirs), `dev` (recon/observer_cli, rebar3_format, rebar3_lint), and example profiles `simple`/`calculator`/`weather`. Plugins: `rebar3_hex`, `rebar3_proper`, `coveralls`. Dialyzer + xref configured. `rebar3_format` config present (paper 100).
- `config/`: `sys.config`, `dev.config`, `prod.config`, `test.config`; `vm.args` at root.
- `Makefile`: targets `compile/clean/test/dialyzer/xref/format/lint/console/release/check`, plus dev/test/docker/publish helpers. `test` target runs `eunit, ct, proper` (ct/proper effectively empty). `check` = clean+compile+xref+dialyzer+test.
- **OTP requirement**: `erl_opts` has `{platform_define, "^2[1-9]|^[3-9]", 'POST_OTP_21'}` (i.e. OTP 21+). `erlmcp.app.src` `runtime_dependencies` cite kernel-6.0/stdlib-3.9/ssl-9.0/inets-7.0 (~OTP 21). CI tests OTP 25–28. Application deps: kernel, stdlib, crypto, public_key, ssl, inets, jsx, jesse.

---

## Quality Smells (concrete)

1. **Abandoned mid-refactor with the weaker module supervised.** `erlmcp_server_sup` starts `erlmcp_server_new` (no subscriptions/progress/templates-list), while the full-featured `erlmcp_server` is off the supervised path and is what the tests cover. Three overlapping server implementations (`erlmcp_server`, `erlmcp_server_new`, `erlmcp_stdio_server`). See `erlmcp_server_sup.erl:23`, `erlmcp_server.erl` vs `erlmcp_server_new.erl`.

2. **References to nonexistent modules.** `erlmcp_transport_sup.erl:20-21` dispatches tcp/http to `erlmcp_transport_tcp_new` / `erlmcp_transport_http_new`, which do not exist — the registry path for tcp/http would crash. Compounded by `erlmcp.erl:143-146` returning `transport_not_implemented` for tcp/http anyway.

3. **Phantom registered process.** `erlmcp.app.src:6` lists `erlmcp_client_sup` in `registered`, but there is no `erlmcp_client_sup` module and `erlmcp_sup` never starts it. Conversely `erlmcp_registry` and `erlmcp_transport_sup` are started but not in `registered`.

4. **Declared dependency never used.** `jesse` (JSON Schema validator) is in deps and app.src but unreferenced in `src/`; tool `inputSchema` is stored and echoed but never validated, so schema validation is effectively absent.

5. **Self-call / behavior mismatch in transports.** `erlmcp_transport_http.erl:62-63` `send/2` does `gen_server:call(self(), ...)` (a process calling itself — deadlock-prone / wrong). The transport behavior (`init/1,send/2,close/1`) is implemented inconsistently across the four transport modules (some are pid-based gen_servers, some operate on a state map, stdio writes stdout directly ignoring state), and `rebar.config` adds `xref_ignores` to paper over signature mismatches.

### Secondary smells
- **Spec inaccuracies** on `handle_call/handle_cast` return types vs actual `{noreply,...}`/`{stop,...}` clauses (e.g. `erlmcp_server.erl:130-131`, `erlmcp_registry.erl:120-121`).
- **Heavy code duplication** of `build_initialize_response/1`, `encode_server_capabilities/1`, `encode_*`, and `normalize_*` between `erlmcp_server` and `erlmcp_server_new`.
- **"broadcast" routing is a placeholder** — `send_notification_via_registry/3` calls `erlmcp_registry:route_to_transport(broadcast, ...)` but the registry has no `broadcast` handling, so server-initiated notifications silently fail to route (`erlmcp_server_new.erl:289-293`, `erlmcp_server.erl:345-349`).
- **Fragile test detection**: `is_test_environment/0` heuristics (`whereis(eunit_proc)`, non-blocking stdin probe) embedded in transport modules (`erlmcp_transport_stdio.erl:148-175`).
- **Stale docs** (`docs/architecture.md`) and missing root `README.md` despite app.src referencing it.
- **CI is shallow**: only compile/xref/eunit/cover with `--min_coverage=0`; no dialyzer/ct/proper; `priv/test` suites excluded from default test profile.
