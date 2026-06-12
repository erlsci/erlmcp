# Creating an MCP Server with erlmcp

This guide walks you from zero to a working MCP server on Erlang/OTP. You will build
a minimal server that runs over stdio, exposes tools and resources, surfaces a
discoverable identity to Claude, and validates inbound payloads at the edge. Every
code block is copy-pasteable; the final result runs cleanly under Claude Desktop.

The guide follows the pattern established by the
[`examples/simple`](../examples/simple/) example — that is the canonical reference
for the finished shape.

---

## What you will build

A running MCP server that:

- Starts over stdio (the transport Claude Desktop uses by default).
- Exposes one tool (`hello`) that returns a greeting.
- Exposes one resource and one prompt for completeness.
- Surfaces a human/model-readable identity block on connect.
- Declares wayfinding metadata so Claude knows which tool to reach for and what
  comes next.

When it works, Claude Desktop will list the tool, call it on request, and receive
a structured response — no more "no tools available."

---

## Prerequisites

- **Erlang/OTP 25 or newer.** OTP 26/27 recommended. Check with `erl +V`.
- **rebar3 3.22 or newer.** Check with `rebar3 version`.
- **Claude Desktop** (optional, for the final end-to-end step). Any MCP-capable
  host works.

---

## 1. Create the project

```bash
mkdir my_mcp_server
cd my_mcp_server
```

Create `rebar.config`:

```erlang
{erl_opts, [debug_info, warnings_as_errors]}.

{deps, [
    {erlmcp, {git, "https://github.com/erlsci/erlmcp.git", {tag, "0.6.0"}}}
]}.

{profiles, [
    {test, [
        {deps, [{meck, "0.9.2"}]},
        {erl_opts, [debug_info, export_all, nowarn_export_all, nowarn_missing_spec]},
        {cover_enabled, true}
    ]}
]}.
```

Create the source directory and the application resource file:

```bash
mkdir -p src config
```

`src/my_mcp_server.app.src`:

```erlang
{application, my_mcp_server, [
    {description, "My first MCP server"},
    {vsn, "0.1.0"},
    {registered, []},
    {mod, {my_mcp_server_app, []}},
    {applications, [kernel, stdlib, erlmcp]},
    {start_phases, [{serve, []}]},
    {env, []}
]}.
```

The `{start_phases, [{serve, []}]}` line is important: it tells OTP to call
`start_phase(serve, ...)` after all applications have started their `start/2`
callbacks. This is how the server begins reading from stdin only after the entire
supervision tree is up — avoiding the startup race that causes "no tools available."

---

## 2. Write the application module

`src/my_mcp_server_app.erl`:

```erlang
-module(my_mcp_server_app).

-behaviour(application).

-export([start/2, start_phase/3, stop/1]).

start(_StartType, _StartArgs) ->
    Config = #{
        name    => <<"my_mcp_server">>,
        version => <<"0.1.0">>,
        purpose => <<"A minimal MCP server — tools, resources, and prompts.">>,
        source  => <<"https://github.com/you/my_mcp_server">>,
        tools   => my_mcp_server:tools(),
        resources => my_mcp_server:resources(),
        prompts => my_mcp_server:prompts()
    },
    case erlmcp_stdio_sup:start_link(Config) of
        {ok, Sup} ->
            register(my_mcp_server_stdio_sup, Sup),
            {ok, Sup};
        {error, _} = Err -> Err;
        ignore -> {error, supervisor_ignored}
    end.

start_phase(serve, _StartType, _Args) ->
    ok = erlmcp_stdio_sup:serve(whereis(my_mcp_server_stdio_sup)),
    ok.

stop(_State) ->
    ok.
```

`start/2` starts the `erlmcp_stdio_sup` supervision tree (which owns the
`erlmcp_server`, transport, and session processes), registers the supervisor under
a name so `start_phase` can reach it, and returns.

`start_phase(serve, ...)` is called by OTP after all start phases complete. It
hands the stdio transport to the session, which begins reading from stdin. Nothing
reads from stdin until this point.

---

## 3. Write the server module

`src/my_mcp_server.erl`:

```erlang
-module(my_mcp_server).

-export([tools/0, resources/0, prompts/0]).

tools() ->
    [erlmcp:make_directory_tool(),
     #{
         name         => <<"hello">>,
         description  => <<"Say hello to a named person or thing.">>,
         input_schema => erlmcp_schema:object([
             erlmcp_schema:field(<<"name">>, erlmcp_schema:string(), [required])
         ]),
         category     => <<"greetings">>,
         when_to_use  => <<"When you want to greet someone by name.">>,
         entry_point  => true,
         handler      => fun(#{<<"name">> := Name}, _Ctx) ->
             {ok, erlmcp:text(<<"Hello, ", Name/binary, "!">>)}
         end
     }].

resources() ->
    [#{
        uri         => <<"file://greeting.txt">>,
        name        => <<"greeting">>,
        description => <<"A static greeting resource.">>,
        mime_type   => <<"text/plain">>,
        handler     => fun(_Ctx) ->
            {ok, erlmcp:text(<<"Hello from erlmcp!">>)}
        end
    }].

prompts() ->
    [#{
        name        => <<"greet">>,
        description => <<"Generate a greeting prompt.">>,
        arguments   => [#{name => <<"person">>, description => <<"Who to greet">>,
                          required => true}],
        handler     => fun(#{<<"person">> := Person}, _Ctx) ->
            Msg = <<"Please greet ", Person/binary, " warmly.">>,
            {ok, [erlmcp:user_message(erlmcp:text(Msg))]}
        end
    }].
```

Three things to note:

1. `erlmcp:make_directory_tool/0` adds a generated `directory` tool that returns a
   categorized listing of all your tools. It is cheap to add and costs nothing if
   the client never calls it.

2. `erlmcp_schema:object/1` with `erlmcp_schema:field/3` builds a JSON Schema for
   your tool's `inputSchema`. Inbound parameters are validated against this schema
   before your handler is called — your handler can assume `name` is always a
   binary. See §6 (Validation at the edge) for why this matters.

3. `category` and `when_to_use` are wayfinding fields (see §5). They are optional
   but highly recommended — they let Claude navigate your tool catalog without
   guessing.

---

## 4. Configure logging to stderr

MCP uses stdin/stdout for the protocol wire. **Log output must go to stderr** or it
will corrupt the framing. Create `config/sys.config`:

```erlang
[
    {kernel, [
        {logger_level, info},
        {logger, [
            {handler, default, logger_std_h, #{
                config => #{type => standard_error}
            }}
        ]}
    ]}
].
```

---

## 5. Create a launch script

`run.sh`:

```bash
#!/bin/bash
# Launch my_mcp_server over stdio.
cd "$(dirname "$0")" || exit 1
rebar3 compile >/dev/null 2>&1
exec erl -noshell \
    -pa $(rebar3 path --ebin -s ' -pa ') \
    -config config/sys \
    -eval 'application:ensure_all_started(my_mcp_server)'
```

```bash
chmod +x run.sh
```

The `exec` replaces the shell process with `erl`, which is what Claude Desktop
expects: a process it can write MCP messages to and read from until it exits.

---

## 6. Compile and run

```bash
rebar3 compile
./run.sh
```

The server starts and waits on stdin. To test it without Claude Desktop, send it a
JSON-RPC initialize request:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | ./run.sh
```

You should see a response followed by a `notifications/initialized` notification.

---

## 7. Make your server discoverable

Discoverability is how Claude knows what your server does, which tool to call first,
and how to navigate from one tool to the next. erlmcp carries this through three
surfaces: the `InitializeResult.instructions` field, per-tool `_meta` wayfinding
in `tools/list`, and the generated `directory` tool. All three are derived from the
same source declarations — they cannot drift.

### 7.1 The identity block

The `name`, `version`, `purpose`, and `source` fields in your app config form the
server's identity block. The `purpose` line is what Claude reads first on connect.
Make it precise:

```erlang
Config = #{
    name    => <<"my_mcp_server">>,
    version => <<"0.1.0">>,
    purpose => <<"A minimal MCP server — tools, resources, and prompts.">>,
    source  => <<"https://github.com/you/my_mcp_server">>,
    ...
}
```

The `purpose` becomes the opening line of the auto-generated `instructions`
returned in `InitializeResult`. You do not need to write `instructions` by hand.

### 7.2 Wayfinding fields

These fields on each tool declaration tell Claude how to navigate your tool catalog:

| Field | Type | Meaning |
|-------|------|---------|
| `category` | `binary()` | Groups related tools together in the directory listing |
| `when_to_use` | `binary()` | One sentence: when should Claude reach for this tool |
| `entry_point` | `boolean()` | `true` for the first tool in a category |
| `next` | `[binary()]` | Which tools to call after this one |
| `returns` | `binary()` | What the tool returns (for the directory listing) |

Example — a two-tool chain:

```erlang
#{
    name        => <<"get_weather">>,
    description => <<"Get current weather for a city.">>,
    input_schema => erlmcp_schema:object([
        erlmcp_schema:field(<<"city">>, erlmcp_schema:string(), [required])
    ]),
    category    => <<"weather">>,
    when_to_use => <<"When you need current weather conditions for a specific city.">>,
    entry_point => true,
    next        => [<<"get_forecast">>],
    returns     => <<"Temperature, condition, and humidity.">>,
    handler     => fun(#{<<"city">> := City}, _Ctx) ->
        {ok, erlmcp:text(<<"Sunny, 22°C in ", City/binary>>)}
    end
},
#{
    name        => <<"get_forecast">>,
    description => <<"Get a multi-day forecast for a city.">>,
    input_schema => erlmcp_schema:object([
        erlmcp_schema:field(<<"city">>, erlmcp_schema:string(), [required]),
        erlmcp_schema:field(<<"days">>, erlmcp_schema:integer([{min, 1}, {max, 7}]),
                            [{default, 3}])
    ]),
    category    => <<"weather">>,
    when_to_use => <<"When you need a multi-day weather forecast.">>,
    returns     => <<"A list of daily forecasts.">>,
    handler     => fun(#{<<"city">> := City, <<"days">> := Days}, _Ctx) ->
        {ok, erlmcp:text(io_lib:format("~B-day forecast for ~s", [Days, City]))}
    end
}
```

The `directory` tool (added via `erlmcp:make_directory_tool/0`) produces a
structured JSON listing of all categories and tools, including the `when_to_use`
and `next` chain, so Claude can orient itself without calling each tool.

### 7.3 Declaring `protocol_features`

If a tool genuinely exercises an advanced MCP protocol feature, declare it:

```erlang
#{
    name              => <<"compute">>,
    protocol_features => [tasks, progress],
    ...
}
```

This declaration appears in `tools/list` under `_meta` (`io.erlmcp/protocol_features`)
and in the `directory` tool output. Only declare features the tool's handler
actually uses — it is a promise to the client.

| Value | Meaning |
|-------|---------|
| `tasks` | Tool starts a long-running task (see `erlmcp_task`) |
| `progress` | Tool emits `notifications/progress` updates |
| `sampling` | Tool calls `request_peer` to initiate server→client sampling |
| `completion` | Resource template or prompt supports `completion/complete` |

See [`examples/calculator`](../examples/calculator/) for `[tasks, progress]` and
`[sampling]` in action; [`examples/weather`](../examples/weather/) for
`[completion]` on a resource template.

---

## 8. Validation at the edge

erlmcp validates inbound payloads at the session boundary using `jesse` (a
JSON Schema validator). You do not need to call `jesse` yourself — it runs
automatically. Understanding what it does and why helps you write correct handlers.

### 8.1 What is validated and when

The validation seam runs at the point where a raw JSON-RPC message enters the
session:

| Error code | Trigger | Meaning |
|-----------|---------|---------|
| `-32600` | Invalid JSON or not an object | Malformed request envelope |
| `-32602` | Params fail `inputSchema` validation | Invalid parameters for the method |
| `-32603` | Handler result fails `outputSchema` or shape check | Server-produced invalid response |

`-32603` is **fail-closed**: if your handler produces a response that does not
pass the outbound shape check, the session returns an error to the client rather
than sending a malformed response. This means payload shape bugs are surfaced
immediately rather than silently causing protocol errors downstream.

### 8.2 Why these checks exist

Three bugs drove the original "no tools available" failure and motivated erlmcp's
validation-at-edge design:

1. **Icon shape** (`§1.3`): Tool icons were declared as `#{type => emoji, emoji => ...}`
   — a shape that was invalid per the protocol schema. The validator now catches
   this at the outbound boundary (`-32603`). The correct shape uses a data-URI in
   the `src` field.

2. **`taskSupport` enum** (`§1.5`): The `taskSupport` field accepted `allowed` as
   a value, which is not in the protocol's enum (`forbidden | optional | required`).
   The validator catches this on both inbound and outbound.

3. **UTF-8 well-formedness** (`§1.4`): Tool names and descriptions containing
   invalid UTF-8 sequences were silently passed through, corrupting the JSON
   encoding. The outbound guard now rejects non-UTF-8 binary content before it
   reaches the wire.

The invariant: **validate at the edge, crash in the interior**. Your handler
receives validated, well-formed parameters and may crash freely on unexpected
conditions — the session will catch the crash, return `-32603` to the client, and
keep running. You only need to handle the cases your schema says are possible.

### 8.3 Writing a correct tool handler

A handler that trusts edge validation:

```erlang
handler => fun(#{<<"city">> := City}, _Ctx) ->
    %% City is guaranteed to be a binary — the schema said string(), required.
    %% No need to check is_binary(City) here.
    Result = do_lookup(City),
    {ok, erlmcp:text(Result)}
end
```

A handler that declares a structured response schema:

```erlang
#{
    name          => <<"add">>,
    description   => <<"Add two integers.">>,
    input_schema  => erlmcp_schema:object([
        erlmcp_schema:field(<<"a">>, erlmcp_schema:integer([]), [required]),
        erlmcp_schema:field(<<"b">>, erlmcp_schema:integer([]), [required])
    ]),
    output_schema => erlmcp_schema:object([
        erlmcp_schema:field(<<"result">>, erlmcp_schema:integer([]), [required])
    ]),
    handler => fun(#{<<"a">> := A, <<"b">> := B}, _Ctx) ->
        {ok, erlmcp:structured(#{<<"result">> => A + B})}
    end
}
```

With `output_schema` declared, the outbound validator verifies that your handler
returns a map matching the schema. Mismatches become `-32603` instead of silent
protocol errors.

---

## 9. Connect to Claude Desktop

Add a server entry to `claude_desktop_config.json`. The location depends on your
OS:

- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "my-mcp-server": {
      "command": "bash",
      "args": ["/absolute/path/to/my_mcp_server/run.sh"]
    }
  }
}
```

Replace `/absolute/path/to/my_mcp_server` with the real path. Restart Claude
Desktop after editing the config. Open a new conversation — the tools icon should
appear in the input toolbar.

**Verify connectivity:**

1. Ask Claude: "What tools do you have access to?" — it should list `hello` and
   `directory`.
2. Ask Claude: "Call the directory tool." — it should return a structured map of
   your tools by category.
3. Ask Claude: "Say hello to Alice." — it should call `hello` with `name: "Alice"`
   and return `"Hello, Alice!"`.

If you see "no tools available," check:

- The path in `claude_desktop_config.json` is absolute and correct.
- `run.sh` is executable (`chmod +x run.sh`).
- `rebar3 compile` ran successfully (no errors).
- Logs in `~/Library/Logs/Claude/` (macOS) contain no MCP-level errors.

---

## 10. Where to go next

The three example servers in this repo demonstrate progressively more of the
erlmcp surface:

### [`examples/simple`](../examples/simple/)

The reference for this howto. Full discoverability (identity block, wayfinding,
directory tool). Inline fun-based handlers. One resource, one prompt. No
advanced protocol features.

### [`examples/calculator`](../examples/calculator/)

Handler behaviour (`-behaviour(erlmcp_server_handler)`), structured output
(`outputSchema`), tool icons, **long-running tasks** with progress notifications
and cancellation, and **server-initiated sampling** (the `explain` tool calls
`request_peer` to ask Claude for an explanation — exercises the bidirectional
channel).

Relevant for: `erlmcp_server_handler`, `erlmcp_task`, `request_peer/3`.

### [`examples/weather`](../examples/weather/)

**Resources** (static and handler-backed), **resource templates** with
`completion/complete`, **prompts with arguments** and completion, multiple
transports (stdio + TCP), and `next`-chain navigation.

Relevant for: `add_resource/2`, `add_resource_template/2`, `add_prompt/2`,
`start_tcp_setup/3`.

---

## Appendix: Reference card

### Starting a stdio server

```erlang
%% In application start/2:
Config = #{
    name    => <<"my_server">>,
    version => <<"0.1.0">>,
    purpose => <<"One sentence: what this server is for.">>,
    source  => <<"https://github.com/...">>,
    tools   => my_server:tools()         %% list of tool maps
    %% resources => my_server:resources(),  %% optional
    %% prompts   => my_server:prompts()     %% optional
},
{ok, Sup} = erlmcp_stdio_sup:start_link(Config),
register(my_server_sup, Sup).

%% In start_phase(serve, ...):
erlmcp_stdio_sup:serve(whereis(my_server_sup)).
```

### Content helpers

```erlang
erlmcp:text(<<"hello">>)              %% text content item
erlmcp:image(Base64Bin, <<"image/png">>) %% image content item
erlmcp:structured(#{<<"key">> => 42}) %% structured (JSON) content
erlmcp:user_message(erlmcp:text(X))   %% prompt message (user role)
erlmcp:assistant_message(erlmcp:text(X)) %% prompt message (assistant role)
```

### Schema builders

```erlang
erlmcp_schema:object([Fields])               %% JSON object
erlmcp_schema:field(Name, Type, Opts)        %% field in an object
erlmcp_schema:string()                       %% string type
erlmcp_schema:integer([{min,0},{max,100}])   %% integer with constraints
erlmcp_schema:number([])                     %% number (float or int)
erlmcp_schema:boolean()                      %% boolean
erlmcp_schema:array(erlmcp_schema:string())  %% array of strings
erlmcp_schema:enum([<<"a">>, <<"b">>])       %% enum (string values)
```

### Return values from handlers

```erlang
{ok, ContentItem}          %% single content item
{ok, [ContentItem, ...]}   %% multiple content items
{error, Code, Message}     %% tool error (surfaced to client as isError: true)
```
