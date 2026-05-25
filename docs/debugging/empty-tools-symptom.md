# Debugging "Empty Tools" Symptoms

Or "Why Your erlmcp Server Starts, Responds, but Never Registers Tools in Claude Desktop"

*A Schema- and Encoder-Centric Diagnosis*

## TL;DR

- **The most likely root cause is jsx's `[]`-vs-`{}` ambiguity colliding with the MCP schema's strict "object" types**: erlmcp depends on `jsx` 3.1.0 (confirmed in `rebar.config` on `erlsci/erlmcp@main`), and any capability sub-field (`tools`, `resources`, `prompts`, `inputSchema.properties`) that is constructed as an empty Erlang list `[]` — or that reaches the encoder as a proplist instead of a map `#{}` — will be emitted as JSON `[]` (an array). The MCP `InitializeResult.capabilities` and Tool `inputSchema` slots are strictly typed as JSON objects, and Claude Desktop's Zod-based validator silently drops servers whose response is structurally JSON-valid but schema-invalid.
- **Three secondary suspects are nearly as common and should be eliminated in parallel**: (a) emitting `"properties": []` instead of `"properties": {}` in `inputSchema` when a tool has no arguments; (b) hard-coded `protocolVersion: "2024-11-05"` against a current Claude Desktop that negotiates `2025-06-18` or `2025-11-25` (mismatch is allowed by spec, but real Claude Desktop builds silently drop the server in this case); (c) accidentally emitting a charlist string (e.g. `"hello"` left as `[104,101,108,108,111]`) as a JSON array of integers in fields like `serverInfo.name` or tool descriptions.
- **Concrete fix**: in `erlmcp_server` / `erlmcp_json_rpc`, force every JSON-object slot to an explicit Erlang map (`#{}` never `[]`), wrap every string field in a `binary()` (never a list), and add a single golden-output test that pipes the `initialize` and `tools/list` responses through `jiffy:decode` or the OTP 27 `json:decode` and asserts on the *decoded* shape — not on the encoded bytes. That test would have caught this in minutes.

---

## Key Findings

### 1. erlmcp uses `jsx` 3.1.0, and that is the single biggest risk factor

Per `rebar.config` on `main` of `erlsci/erlmcp`, the only JSON dependency is `{jsx, "3.1.0"}` (alongside `jesse` for schema validation, which is a *validator*, not an encoder). The maintainer (@oubiwann) explicitly flags this as a known risk in the open "0.6.0 Plan" issue (#10): *"JSON library choice (`jsx` vs `jsone`/`thoas`) — Decide in M0; isolate behind `erlmcp_codec` so it's reversible."* The fact that the JSON-library choice is itself a planned rework item is the loudest signal in the codebase that subtle encoding behaviour has bitten people.

`jsx`'s historical empty-object ambiguity is documented at `talentdeficit/jsx` issue #22, opened October 2012 by @defunerik, who wrote verbatim: *"Wouldn't it be nice to just use [] for the empty object? But that is the representation of an empty Array. Arrays with one or more elements can be differentiated from an Object, for sure, but what about the empty case?"* The library settled on the convention `[{}]` for an explicit empty object in legacy proplist mode. With OTP-map support added in jsx 3.x, `jsx:encode(#{})` correctly produces `"{}"`, but `jsx:encode([])` still produces `"[]"`. If any code path in erlmcp lands an empty list in a slot the MCP schema requires to be an object, the wire bytes look fine to a syntactic JSON parser but the validator on the client side rejects the response.

This is the exact failure mode you see: the server starts, JSON-RPC framing is correct, `initialize` returns a well-formed-looking response, and yet the client never lists any tools and never marks the server "ready."

### 2. The MCP schema strictly types the slots most likely to drift

From the official `schema.ts` (current stable revision 2025-11-25, per the official MCP blog post "One Year of MCP: November 2025 Spec Release"; a further 2026-07-28 Release Candidate is also published) and the Rust mirror at `rust-mcp-schema`:

- `InitializeResult` has **required** fields `protocolVersion: string`, `capabilities: ServerCapabilities`, `serverInfo: Implementation`. The Rust mirror makes the required set explicit: `"required": [ "capabilities", "protocolVersion", "serverInfo" ]`.
- `ServerCapabilities` is `{ experimental?, logging?, completions?, prompts?, resources?, tools? }` — every sub-field is itself an **object** (possibly empty), never an array. The minimal valid declaration for "I have tools" is `"tools": {}`.
- `Tool` requires `name`, `description`, `inputSchema`. `inputSchema` MUST be a valid JSON-Schema object, MUST have `"type": "object"`, and the current spec is explicit: "MUST be a valid JSON Schema object (not null). For tools with no parameters, use `{ "type": "object", "additionalProperties": false }` … or `{ "type": "object" }`." Crucially, if `properties` is present it must be an object, not an array.

The exact failure of "properties as array" has been observed in production. The WordPress/mcp-adapter issue #35 captures the Cursor IDE error verbatim: `Error listing tools: [ { "code": "invalid_type", "expected": "object", "received": "array", "path": [ "tools", 3, "inputSchema", "properties" ], "message": "Expected object, received array" } ]`. Claude Desktop's validator is the same shape (Zod-based) — it just doesn't show the message to the user; it silently fails to register the server. The Anthropic `claude-code` issue tracker has multiple reports of this exact fingerprint — most notably issue #2682, "MCP Tools Not Available in Conversation Interface Despite Successful Connection," whose body states verbatim: *"Claude Desktop successfully connects to MCP server and lists tools via tools/list requests, but the tools never become available in the conversation interface for actual use. Claude Desktop Version: 0.11.3 (latest as of Dec 2024)."*

### 3. Empty `capabilities`/`tools`/`properties`: the four-way confusion table

For an Erlang/Elixir developer this is the most error-prone surface, because *four* different Erlang terms can plausibly mean "empty object" depending on which encoder you use:

| Erlang term | jsx 3.x | jiffy | jsone (default) | jsone `{object_format, proplist}` | OTP 27 `json` | thoas |
|---|---|---|---|---|---|---|
| `#{}` | `{}` ✅ | `{}` ✅ | `{}` ✅ | `{}` ✅ | `{}` ✅ | `{}` ✅ |
| `[]` | `[]` (array) ❌ | `[]` (array) ❌ | `[]` (array) ❌ | `[]` (array) ❌ | `[]` (array) ❌ | `[]` (array) ❌ |
| `[{}]` | `{}` ✅ (legacy) | error | `[{}]` confusion | `{}` ✅ | error/array | error |
| `{[]}` | error | `{}` ✅ (jiffy convention) | `{}` ✅ (tuple format) | error | error | error |

The cell to internalize is row 2: **every encoder emits an empty Erlang list as a JSON array**. There is no encoder that "guesses" an empty list is an empty object. So if `erlmcp_server` builds `Capabilities = #{ <<"tools">> => #{} }` and then a later pass does `maps:to_list/1` (e.g. to filter or merge) and the result happens to come out empty, you have just rewritten `{}` to `[]` on the wire.

### 4. Charlist-vs-binary: the "string emitted as `[104,101,...]`" bug

Erlang has no native string type; `"hello"` is `[104,101,108,108,111]`. Every Erlang JSON encoder treats a plain list as a JSON array unless told otherwise:

- **`jsx`**: `jsx:encode("hello")` produces `"hello"` *only* because jsx applies a heuristic that detects all-printable codepoint lists and treats them as strings. That heuristic is fragile — lists containing values ≥ 128 (e.g. `"héllo"`) or zero will be emitted as `[104,233,108,...]`.
- **`jiffy`**: "Jiffy only understands UTF-8 in binaries. End of story." (`davisp/jiffy` README, verbatim). A charlist becomes a JSON array of integers.
- **`jsone`**: same — only `binary()` and `atom()` are strings; a list is an array. Documented in its type table: `<<"abc">> -> "abc"` but `[1,2,3] -> [1,2,3]`.
- **OTP 27 `json`**: `encode_value()` is typed as `integer() | float() | boolean() | null | binary() | atom() | [encode_value()] | encode_map(...)`. A list is encoded as a JSON array by `json:encode_list/1`; strings must be `binary()`.

The README of erlmcp uses binary keys (`<<"name">>`) and binary values (`<<"World">>`) — which is correct. But the moment a developer writes `serverInfo => #{name => "my-server", ...}` (an Erlang string literal in a quick-and-dirty test) with jsone or jiffy, `name` ships as an array of integers, which Claude Desktop will reject as an `Implementation.name` violation (Implementation requires `name: string`).

### 5. protocolVersion mismatch is real and *can* be silent

erlmcp's open 0.6.0 plan (#10) explicitly lists "Capability + protocol-version negotiation over a declared supported-version set" as M1 work — meaning current 0.5.x **does not negotiate**; it ships a hard-coded version. The MCP spec says: "If the client cannot support this version, it MUST disconnect." A documented real-world case is the April 2026 Figma Forum post by Andrei Carvalho, "MCP extension stops responding after Claude Desktop update — protocol version mismatch," which captures the failure verbatim: *"Claude Desktop now negotiates 2025-11-25, while the Figma extension responds with 2025-06-18 … Any tool call → no response / timeout after 4 min … Client transport closed (intentional shutdown)."* The current stable spec is `2025-11-25` (per the official MCP blog announcement), with a 2026-07-28 Release Candidate also published; older Claude Desktops still negotiate `2024-11-05`, `2025-03-26`, or `2025-06-18`. If erlmcp's hard-coded value is older than what the user's CD/CDC build accepts (or, in the Figma case, newer), the connection may complete `initialize`, the client may even call `tools/list` once, and then go quiet — exactly your symptom.

However: a mismatch typically produces *some* log line in `~/Library/Logs/Claude/main.log` (macOS) or `%APPDATA%\Claude\logs\` (Windows). A pure encoder defect typically produces *none*. If your stderr-side log shows the client send `notifications/initialized` after your `initialize` response, then the handshake itself succeeded and the silent failure is on a downstream schema field, not on protocolVersion.

### 6. The `notifications/initialized` and capability advertisement contract

Two protocol mistakes specifically cause "server connected but no tools":

- **Server emits a notification before receiving `initialize`.** The `ruvnet/claude-flow` issue #898 (opened Dec 6, 2025 by @DonQuilatte against claude-flow v2.7.42-alpha) captured this exactly: the server sent a `server.initialized` notification on stdout *before* responding to `initialize`. Claude's client rejected it with the verbatim Zod error *"Zod validation error: invalid_union - Required fields missing (id, method, result) Unrecognized key(s) in object: 'error'"* and then never trusted the session. Make sure your erlmcp boot sequence does not write anything to stdout before the first request arrives. (And `notifications/initialized` is a *client → server* notification, never the reverse.)
- **Server omits `tools` from `capabilities` while still answering `tools/list`.** Some MCP clients will not call `tools/list` if you didn't declare `capabilities.tools` in the initialize response (Portkey, mcpevals.io guides). Others will call it anyway but then ignore the answer. You must emit `"capabilities": {"tools": {}}` (or `{"tools": {"listChanged": false}}`) — and that inner `{}` is exactly where the jsx/empty-map bug bites.

### 7. Elixir-side gotchas (for comparison or fallback)

- **Jason**: `Jason.encode!(%{})` correctly produces `"{}"`; `Jason.encode!([])` produces `"[]"`. Same trap as Erlang. Atom keys serialize fine; `nil` serializes to `null`. Structs need `@derive Jason.Encoder` or an explicit `defimpl` — otherwise you get a `Protocol.UndefinedError` at runtime, which usually crashes the process rather than producing malformed JSON (preferable failure mode).
- **Hermes MCP / Anubis MCP** (`cloudwalk/hermes-mcp`, `zoedsoupe/anubis-mcp`) build capabilities through a typed struct (`use Hermes.Server, capabilities: [:tools]`) and a `register_tool/3` macro with a typed `:input_schema`, which prevents most of these encoding mistakes by construction. If you find yourself fighting jsx empty-object bugs for more than an afternoon, switching to Anubis (the actively maintained Hermes fork) on Elixir is a credible escape hatch — but it doesn't help an Erlang-only stack.
- **Newer Elixir on OTP 27+** can use `:json` directly and bypass Jason entirely. Same encoding rules as Erlang `json:encode/1`.

### 8. Numeric coercion: a smaller but real risk

`jsone` defaults to scientific notation: `jsone:encode(1.23)` produces `<<"1.22999999999999998224e+00">>`. JSON-RPC and MCP schemas accept this (it's valid JSON), but some downstream consumers (older JSON-Schema validators in particular) treat large-precision scientific notation as suspicious. If `inputSchema.properties.x.default` is a float, prefer `jiffy` or pass `{float_format, [{decimals, N}, compact]}` to jsone. The OTP 27 `json` and `jsx` produce shortest round-trip decimal representations by default and are safer here.

`jiffy` has the inverse quirk: it returns `iolist()` from `encode/1` "even though it returns a binary most of the time" (verbatim from the `davisp/jiffy` README). If you write that directly to stdout without `iolist_to_binary/1`, you may emit a partial frame on some code paths.

---

## Details: The Exact Diagnostic Sequence to Run

Given the user's description ("initialize gets a valid JSON-RPC response on stdout, registry boots, server visible but no tools"), here is the order I would investigate, fastest to slowest:

1. **Capture the literal bytes** of the `initialize` response and the (potentially auto-invoked) `tools/list` response that your erlmcp process writes to stdout. Use `script(1)`, `tee`, or wire a debug logger on the transport. Do **not** trust your encoder's `io_lib:format` rendering — it pretty-prints empty maps as `#{}` even when jsx emitted `[]`.

2. **Diff the bytes against a Python reference server's bytes** (e.g. `mcp.server.fastmcp` "Echo" server). The two responses should be structurally identical at the JSON level. The first divergence is almost certainly your bug. Pay particular attention to:
   - `result.capabilities` — should be `{...}`, watch for `[]`.
   - `result.capabilities.tools` — should be `{}` or `{"listChanged":false}`, watch for `[]` or missing.
   - `result.serverInfo.name` / `version` — should be strings, watch for `[104,101,...]`.
   - The `tools/list` response: `result.tools` is an array; each tool's `inputSchema` is an object; `inputSchema.properties` is an object (or absent). Watch for `"properties": []`.

3. **Re-parse your own output and re-encode it.** Pipe your `initialize` response through `jiffy:decode/1` (or `json:decode/1` on OTP 27) and `io:format("~p~n")` the result. If the decoded term has `[]` anywhere you expected `#{}`, you've found your bug.

4. **Test with MCP Inspector** (`npx @modelcontextprotocol/inspector`) against your stdio command. The Inspector's UI surfaces Zod validation errors that Claude Desktop hides; if your tools list shows as 0 but the raw `tools/list` response in the network pane shows tools, you have a schema-validation rejection on the client side.

5. **Audit every `Capabilities = #{ ... }` literal** in erlmcp_server and your own server module. Make sure no code path runs `maps:to_list/1` on these maps without immediately reconstructing a map. The pattern `Capabilities1 = maps:from_list([{K,V} || {K,V} <- maps:to_list(Capabilities0), V =/= undefined])` is fine; the pattern that drops back to a proplist `[{K,V} || ...]` and then ships that to `jsx:encode` is the bug.

6. **Audit every string literal** flowing into outbound JSON. In erlmcp idiom they should all be `<<"...">>`. Look for accidental `"hello"` (Erlang string = charlist = JSON array of integers with most encoders). Watch especially in tool `description` fields and `serverInfo.name`.

7. **Confirm `protocolVersion`**: log the literal value your server sends in the `initialize` response. If it's `"2024-11-05"` and your Claude Desktop log shows the client opened with `"2025-06-18"` or `"2025-11-25"`, that's a possible cause; reply with the version the client sent rather than your hard-coded value.

8. **Confirm capability declaration**: make sure your `InitializeResult.capabilities` contains the literal key `"tools"` mapping to `{}` (or an object with `listChanged`). Without this, Claude Desktop may not call `tools/list` at all.

9. **Confirm `inputSchema` is per-spec** for *every* tool: `{"type": "object"}` minimum, never `null`, never `[]`. If a tool takes no args, ship `{"type": "object", "additionalProperties": false}`. This is the closest thing the spec has to a single "definitely will pass" template.

---

## Recommendations

**Immediate (next 30 minutes):**

- Run step 1 above. Get the literal bytes of your `initialize` response into a file. Open it in a text editor. Eyeball it for `"capabilities":[]`, `"tools":[]`, `"properties":[]`, or any field whose value looks like `[104,101,108,...]`. Nine times out of ten, that's the bug, and you don't need any of the rest of this document.

**Short-term (today):**

- Introduce a single Erlang module `erlmcp_codec` (the maintainer is already planning this — see issue #10) that wraps `jsx:encode/1` and:
  - rejects any list term in a position the spec requires to be an object (use Dialyzer specs and a runtime guard);
  - converts any `string()` (i.e. `[char()]`) to `unicode:characters_to_binary/1` before encoding;
  - has a single corresponding `decode/1` that round-trips your own output for golden tests.
- Add one golden test: build your `initialize` response, encode it, decode it with a *different* library (e.g. `jiffy:decode/2` with `[return_maps]`), and assert on the decoded shape: `#{<<"result">> := #{<<"capabilities">> := Caps, <<"serverInfo">> := #{<<"name">> := Name}}}` where `is_map(Caps)` and `is_binary(Name)`. This single test catches both the empty-map bug and the charlist bug.

**Medium-term (this week):**

- Pin the `protocolVersion` your server advertises to match the client's request (echo it back) rather than hard-coding. The spec allows you to choose, but echoing what the client sent maximizes compatibility across CD/CDC versions.
- Decide between jsx, jsone, thoas, and OTP 27 `json` for erlmcp. **Recommendation: OTP 27 `json` if you're on OTP 27+** — it's in-tree, has no proplist mode, and its `encode_value()` type explicitly forbids the ambiguous cases. `thoas` is the next-best portable option. Avoid `jiffy` for an MCP server because its iolist return type ("encode/1 returns iodata() even though it returns a binary most of the time," per the README) is one extra place to forget `iolist_to_binary/1` and emit a corrupt frame.
- File the bug back on `erlsci/erlmcp` once you've isolated it. The maintainer is actively planning a 0.6.0 rewrite and this is exactly the class of finding they're soliciting.

**Benchmarks that would change my recommendation:**

- If the literal bytes you capture in step 1 are byte-identical to a Python FastMCP server's bytes, the problem is *not* in encoding. In that case, escalate to: (a) double-check `protocolVersion` negotiation; (b) inspect `~/Library/Logs/Claude/mcp-server-<name>.log` (macOS) or `%APPDATA%\Claude\logs\` (Windows) for the client-side rejection reason; (c) verify your server actually reads `notifications/initialized` from stdin and doesn't sit blocked on a pre-handshake send.
- If Claude Desktop logs explicitly say "Extension `<name>` not found in installed extensions" (see `anthropics/claude-code` #22299), you have hit a CD-side regression unrelated to your payload, and the fix is to package as a `.mcpb` extension or downgrade CD.

---

## Caveats

- I could not retrieve the raw source of `erlmcp_server.erl` and `erlmcp_json_rpc.erl` through GitHub's HTML interface during this investigation; the strong-but-indirect finding that erlmcp uses `jsx` is from `rebar.config` (directly confirmed) and the maintainer's own statements in issue #10 (directly confirmed). The specific code path that produces an `[]`-vs-`{}` defect, if one exists in the current 0.5.1 release, was not pin-pointed to a line number. The diagnostic sequence above is structured to find it empirically in minutes.
- Some of the "tools don't appear" issues in the Anthropic tracker (`claude-code` #5241, #29443, #14807, #22299) are confirmed *client*-side bugs (Windows stdio pipe handling, extension-registry regressions in CCD v2.1.22, etc.). A small share of these reports are not the user's fault. If your encoding looks pristine and the symptom persists, capture the Claude Desktop logs and compare against the open Anthropic issues before spending more time on payload audits.
- The MCP protocol revisions move quickly: `2024-11-05` → `2025-03-26` → `2025-06-18` → `2025-11-25` (current stable per the November 2025 spec release) → 2026-07-28 Release Candidate. Recommendations here are accurate for the current Claude Desktop builds as of May 2026, but check the `protocolVersion` field in your own client's logs before assuming.
- I deliberately did not investigate stdio I/O wiring, group leader leakage, or file descriptor inheritance per the user's instruction that those are already understood.
