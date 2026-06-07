# Phase 6 — Claude Desktop Acceptance Test

> Hand-driven smoke test per example server. Documents the procedure,
> observed state, and verdict. Created as part of P6-M6 to close the
> original "no tools available" arc against the consumer that surfaced it.

## Pre-condition: does Claude Desktop surface `InitializeResult.instructions`?

**Status:** Untested — CC does not have access to a running Claude Desktop
instance. This acceptance document records the **test procedure** for CDC or
Duncan to execute. The verdicts below are **placeholder (pending)** until a
human runs the procedure against a real Claude Desktop installation.

**If CD surfaces `instructions`:** the model sees the auto-generated identity +
category overview + directory pointer at first contact. The M3 machinery bet
pays off directly.

**If CD does not surface `instructions`:** the `directory` tool carries the
orientation. The model must call `directory` to get the same content. This is
still a pass for M6 purposes — the content exists and is accessible through at
least one surface.

---

## Simple Server

### Procedure

1. Add to Claude Desktop `claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "simple": {
         "command": "/path/to/erlmcp/examples/simple/run.sh"
       }
     }
   }
   ```
2. Start Claude Desktop. Open a new conversation.
3. Verify tools are listed (check the tools icon or ask "What tools do you have?").
4. Ask Claude to call the `directory` tool.
5. Ask Claude to call `echo` with text "hello".
6. Ask Claude to call `add` with a=3, b=4.

### Expected state

- `initialize` succeeds (CD connects, no "no tools available").
- `tools/list` returns 3 tools: `echo`, `add`, `directory`.
- `directory` returns a structured orientation with the server identity
  ("simple"), purpose, and tool categories.
- `echo` returns "hello".
- `add` returns "7".

### Verdict

**Pending** — requires human execution against Claude Desktop.

### Follow-ups

None anticipated. If CD shows "no tools available," check the `run.sh` path
and the MCP log for payload errors.

---

## Calculator Server

### Procedure

1. Add to Claude Desktop config:
   ```json
   {
     "mcpServers": {
       "calculator": {
         "command": "/path/to/erlmcp/examples/calculator/run.sh"
       }
     }
   }
   ```
2. Start Claude Desktop. Open a new conversation.
3. Verify tools are listed.
4. Call `directory` — verify it shows arithmetic + demo categories, and that
   `slow_compute` shows `[tasks, progress]` and `explain` shows `[sampling]`
   in protocol features.
5. Call `add` with a=10, b=32 — verify structured result `{result: 42}`.
6. Call `slow_compute` with steps=5 — verify progress notifications appear
   (if CD surfaces them) and the final result arrives.
7. Call `explain` with expression="2+3" — verify the sampling round-trip:
   CD should receive a `sampling/createMessage` request, generate an
   explanation, and return it as the tool result.

### Expected state

- `initialize` succeeds.
- `tools/list` returns 7 tools (add, subtract, multiply, divide,
  slow_compute, explain, directory).
- `directory` shows structured categories with protocol feature annotations.
- `add` returns structured output with `result: 42`.
- `slow_compute` completes after progress notifications.
- `explain` round-trips a sampling request (if CD supports sampling).

### Verdict

**Pending** — requires human execution against Claude Desktop.

### Follow-ups

- If `explain` fails because CD doesn't support `sampling/createMessage`,
  document the error and mark as **partial** (sampling is a spec-optional
  feature; the tool gracefully returns an error).
- If progress notifications don't surface in CD's UI, that's a CD limitation,
  not an erlmcp defect — mark as **pass** with a note.

---

## Weather Server

### Procedure

1. Add to Claude Desktop config:
   ```json
   {
     "mcpServers": {
       "weather": {
         "command": "/path/to/erlmcp/examples/weather/run.sh"
       }
     }
   }
   ```
2. Start Claude Desktop. Open a new conversation.
3. Verify tools are listed.
4. Call `directory` — verify weather category with `get_weather` and
   `get_forecast`.
5. Call `get_weather` with city="london" — verify temperature + condition.
6. Call `get_forecast` with city="paris", days=3 — verify 3 days of data.
7. If CD supports resource browsing, verify `weather://current/london` is
   accessible.

### Expected state

- `initialize` succeeds.
- `tools/list` returns 3 tools (get_weather, get_forecast, directory).
- `directory` shows the weather category.
- `get_weather` returns mock weather data.
- `get_forecast` returns multi-day forecast.

### Verdict

**Pending** — requires human execution against Claude Desktop.

### Follow-ups

None anticipated for basic tool functionality. Resource template completion
requires CD to support `completion/complete`, which is spec-optional.

---

## Summary

| Example | Verdict | Notes |
|---------|---------|-------|
| simple | pending | Awaiting human test |
| calculator | pending | Awaiting human test; sampling depends on CD capability |
| weather | pending | Awaiting human test; completion depends on CD capability |

**The test procedure is documented and reproducible.** CDC or Duncan should
execute it in a focused session per example and update the verdicts.
