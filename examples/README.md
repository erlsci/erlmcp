# erlmcp Examples

Runnable MCP server examples demonstrating the erlmcp 0.6.0 feature set.
Each example compiles and is smoke-tested in CI. The discoverability
invariants (DISC-1/2/3) are CI-enforced for every example.

## Prerequisites

- Erlang/OTP 25+
- rebar3

## Examples

### Calculator (`calculator/`)

**Features demonstrated:** `erlmcp_server_handler` behaviour, structured
output (`outputSchema`), discoverability (instructions, `_meta`
wayfinding, directory tool, entry points, `next` chains), icons, task
support (long-running with progress + cancel), **server-initiated
sampling** (`explain` tool calls `request_peer` to ask the client for an
explanation — exercises the bidirectional MCP channel when run under
Claude Desktop).

**Run:**

```bash
./examples/calculator/run.sh
```

**Claude Desktop config:**

```json
{
  "mcpServers": {
    "erlmcp-calculator": {
      "command": "bash",
      "args": ["<PATH>/erlmcp/examples/calculator/run.sh"]
    }
  }
}
```

**What to expect:** On `initialize`, Claude receives an `instructions`
overview listing the `arithmetic` and `demo` categories with `add` as
the entry point. `tools/list` returns each tool with `_meta` wayfinding
under `io.erlmcp/`. The `directory` tool returns a categorized JSON
listing. Calling `explain` triggers server→client sampling — Claude
Desktop generates an explanation.

**Tests:**

```bash
rebar3 ct --suite=erlmcp_example_calculator_smoke_SUITE
rebar3 ct --suite=erlmcp_example_calculator_SUITE
rebar3 ct --suite=erlmcp_example_disc_SUITE
```

---

### Simple (`simple/`)

**Features demonstrated:** Inline fun-based tool registration (no
handler module), resource, prompt, directory tool, full discoverability
wayfinding on every tool.

**Run:**

```bash
./examples/simple/run.sh
```

**Claude Desktop config:**

```json
{
  "mcpServers": {
    "erlmcp-simple": {
      "command": "bash",
      "args": ["<PATH>/erlmcp/examples/simple/run.sh"]
    }
  }
}
```

**What to expect:** `instructions` lists the `utility` category with
`echo` as entry point. Two tools (`echo`, `add`) with full `_meta`
wayfinding. One resource (`file://example.txt`), one prompt (`greet`).

**Tests:**

```bash
rebar3 ct --suite=erlmcp_example_simple_SUITE
rebar3 ct --suite=erlmcp_example_disc_SUITE
```

---

### Weather (`weather/`)

**Features demonstrated:** Resources (static + handler-backed), resource
templates with tab-completion, prompts with arguments and completion,
directory tool, full discoverability wayfinding, multiple transports
(stdio + tcp), forecast tool demonstrating `next` chaining.

**Run:**

```bash
# Stdio
./examples/weather/run.sh

# TCP (from a shell)
rebar3 as weather shell
1> weather_server:start_tcp("localhost", 9000).
```

**Claude Desktop config:**

```json
{
  "mcpServers": {
    "erlmcp-weather": {
      "command": "bash",
      "args": ["<PATH>/erlmcp/examples/weather/run.sh"]
    }
  }
}
```

**What to expect:** `instructions` lists the `weather` category with
`get_weather` as entry point. `get_weather` → `get_forecast` via `next`.
Tab-completion on the `{city}` template parameter returns matching
cities. The `weather_report` prompt supports completion on both `city`
and `units` arguments.

**Tests:**

```bash
rebar3 ct --suite=erlmcp_example_weather_smoke_SUITE
rebar3 ct --suite=erlmcp_example_weather_SUITE
rebar3 ct --suite=erlmcp_example_disc_SUITE
```

---

## Feature Coverage Matrix

| Feature | Calculator | Simple | Weather |
|---------|:---:|:---:|:---:|
| Tools (handler behaviour) | ✓ | | |
| Tools (inline funs) | | ✓ | ✓ |
| Structured output | ✓ | | |
| Resources | | ✓ | ✓ |
| Resource templates + completion | | | ✓ |
| Prompts + completion | | ✓ | ✓ |
| Discoverability (instructions) | ✓ | ✓ | ✓ |
| Discoverability (directory tool) | ✓ | ✓ | ✓ |
| Discoverability (`_meta` wayfinding) | ✓ | ✓ | ✓ |
| Icons | ✓ | | ✓ |
| Tasks (long-running + progress) | ✓ | | |
| Server→client sampling | ✓ | | |
| Multiple transports | | | ✓ |
| `next` graph chaining | ✓ | ✓ | ✓ |

## Discoverability

Every example enforces the DISC invariants (CI-guarded):

- **DISC-1:** 100% tool metadata coverage (every tool has `category` +
  `when_to_use`)
- **DISC-2:** Dangling-free `next` graph (every `next` target is a
  registered tool)
- **DISC-3:** Orphan-free (every tool is reachable from an entry point
  via `next`)
