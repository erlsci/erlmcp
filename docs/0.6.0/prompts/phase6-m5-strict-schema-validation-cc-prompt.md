# CC Prompt — strict MCP schema validation, both directions (SHOULD ⇒ MUST)

> Imperative brief. Drive **all** protocol payload validation from the canonical MCP
> schema (`docs/0.6.0/planning/schema.ts`, `LATEST_PROTOCOL_VERSION = "2025-11-25"`),
> generate a JSON Schema from it, and enforce it at **both** edges — inbound requests
> *and* the messages **we emit**. Interpretation rule for this work: **every spec
> SHOULD/RECOMMENDED is treated as MUST.** Where the spec offers alternatives and one is
> weaker, we take the stronger one as an absolute command. This is a hardening milestone;
> it needs its own ledger before code (see "Process" below).

## Why (root motivation)

Claude Desktop reports **"this connector has no tools available"** for the example
servers even though `initialize` round-trips. That is the classic signature of a
`tools/list` result that is *structurally well-formed JSON-RPC* but **violates the MCP
schema** — a missing required field or an out-of-enum value the client silently rejects.
We already know of one: `calculator_server`'s `slow_compute` declares
`task_support => allowed`, but the schema enum is `forbidden | optional | required`
(`allowed` is not a member). There are almost certainly others. Hand-auditing payloads
does not scale and is exactly what a machine-checked schema is for. **We never want to
emit a payload that fails the protocol schema, and we want the failure to surface in CI,
not in a client's silent rejection.**

## What exists today (build on these seams — do not invent parallel ones)

- `erlmcp_schema:validate/2` already wraps **jesse** (`jesse:validate_with_schema/2`).
  Today it is used only for **per-tool** input/output arg validation
  (`erlmcp_server_session.erl` ~L523, ~L589) — i.e. a tool's own `inputSchema`, *not*
  the MCP protocol envelope. Reuse this jesse wrapper; do not add a second validator.
- All outbound protocol messages funnel through exactly three functions in
  `erlmcp_server_session.erl`: **`send_response/3`**, **`send_raw/2`**, **`send_error/4`**.
  These are the single chokepoints for outbound validation. (Mirror the equivalent
  funnels in `erlmcp_client_session.erl`.)
- Inbound classification is `erlmcp_json_rpc:decode_and_classify/1` /
  `decode_and_classify_any/1` — structural JSON-RPC only, no MCP-schema check of params.
- **Locked decisions still bind:** JSON only via `erlmcp_codec` (no stray `jsx:` calls);
  jesse is *the* validator (swapping it requires an amendment, not a quiet substitution);
  min OTP 25; no macros-for-logic; no `_new` forks; per-module coverage ≥90%.

## Design — the pipeline

### 1. Schema artifacts (committed, version-pinned to 2025-11-25)

Create `priv/schema/`:

- `schema.ts` — the canonical source, copied (or symlinked at build) from
  `docs/0.6.0/planning/schema.ts`. Single source of truth. Pin the protocol version.
- `mcp.schema.json` — **generated** from `schema.ts`. Committed to the repo so the
  Erlang test path never needs Node at runtime.
- `should-as-must.overlay.json` — a **hand-curated** JSON Schema overlay that encodes
  the SHOULD ⇒ MUST tightenings the generated schema can't express (TSDoc prose isn't
  in the types). Every entry carries a comment citing the exact spec section it enforces.
- `mcp.strict.schema.json` — generated artifact = `mcp.schema.json` deep-merged with the
  overlay. **This is the schema the validator loads.** Committed.

### 2. Generation toolchain

- Generate with **`ts-json-schema-generator`** (npm). Emit the *strictest* output:
  `additionalProperties: false` everywhere, required fields required, no implicit
  widening, `strictNullChecks` on. A small wrapper script under `scripts/`
  (e.g. `scripts/gen-mcp-schema.sh`) does: generate → deep-merge overlay → write
  `mcp.strict.schema.json`.
- **jesse draft-compatibility is the #1 risk — verify it explicitly.** jesse targets
  draft-04/06; `ts-json-schema-generator` emits draft-07 and the MCP schema leans on
  `const` discriminators and `anyOf` unions. Confirm jesse can *load and validate
  against* `mcp.strict.schema.json` on the **OTP 25–28** matrix. If a draft-07-only
  keyword (`if/then/else`, etc.) trips jesse, either (a) post-process the generated
  schema into a jesse-digestible form (documented transform), or (b) **raise an
  amendment** — do **not** silently swap jesse for another validator (locked decision).
- CI drift guard: a job regenerates `mcp.strict.schema.json` from `schema.ts` + overlay
  and asserts `git diff --exit-code` is clean — the committed artifact can never drift
  from its source. (This job may install Node; the Erlang matrix jobs must not need it.)

### 3. The SHOULD ⇒ MUST overlay (judgment work — document every entry)

Walk the 2025-11-25 spec and the TSDoc comments in `schema.ts`. For each SHOULD /
RECOMMENDED that is mechanically checkable, add an overlay tightening and a one-line
citation. At minimum, evaluate (non-exhaustive — find the rest):

- Tool / prompt / resource definitions SHOULD carry a human-readable `description` ⇒
  make `description` **required**.
- `tools/list` (and the other `*/list` results) — every field the spec marks
  recommended-present on a `Tool` ⇒ required.
- Wherever the spec says a field SHOULD be one of an enumerated set ⇒ enforce the enum
  (this catches `task_support => allowed`).
- `_meta` key grammar (the `io.erlmcp/` / reverse-DNS prefix rule already in our
  discoverability design) ⇒ enforce as a pattern, not advisory.

Produce a table in the ledger: *spec section → SHOULD text → MUST tightening → overlay
location*. A SHOULD we deliberately do **not** enforce gets a row too, with the reason.

### 4. Wiring — validate at both edges

Add `erlmcp_protocol_schema` (or extend `erlmcp_schema`; pick one and document it). It
loads `mcp.strict.schema.json` **once** into `persistent_term` at app start and exposes:

- `validate_inbound(Method :: binary(), Params :: map()) -> ok | {error, Errors}`.
- `validate_outbound(MessageKind, Json :: map()) -> ok | {error, Errors}` where
  `MessageKind` selects the right schema definition (e.g. `initialize_result`,
  `list_tools_result`, a notification, an error object).

**Inbound** (validate-at-edge): after `decode_and_classify*`, validate the request's
method+params against the schema. Failure ⇒ JSON-RPC error to the client
(`-32600` invalid request / `-32602` invalid params), never a crash.

**Outbound** (the new guard — this is what catches the `tools/list` bug): inside
`send_response/3`, `send_raw/2`, `send_error/4`, validate the payload **before** it
reaches the transport. Semantics — **fail closed:**

- A failing outbound payload is *our* bug, not the client's. Under test/CI it **must
  crash loudly** (let-it-crash in the request worker) so the test suite catches it; the
  session supervisor survives. At the session↔worker boundary translate that crash to a
  `-32603` internal error to the client and `logger:error/2` the schema violation to
  **stderr** (never stdout — stdout is the protocol channel).
- Validation is **always on** (no "skip in prod" escape hatch — strictness is the point).
  If profiling later shows it's hot, optimize the validator; do not gate it off. A single
  documented switch may exist for test fixtures that *intentionally* assert rejection.

### 5. Fix what the new guard flags

Turning on outbound validation will fail tests until the emitted payloads conform. Fix
the producers, not the schema:

- `calculator_server` `slow_compute`: `task_support => allowed` ⇒ a valid enum member
  (`optional` is the likely intent — confirm against the tool's behaviour).
- `erlmcp_server_session:format_tool_for_list/1` and the other `format_*` emitters:
  bring every emitted object into conformance (required fields present, correct types,
  `taskSupport` serialized as a schema-valid string).
- Re-run the stdio round-trip test (`test/scripts/test_stdio_roundtrip.sh`) and, once the
  separate stdio-I/O bug is closed, confirm Claude Desktop now lists tools.

## Process (house rigour — do this first)

This is milestone-sized. **Before writing code, draft the ledger**
(`docs/0.6.0/milestones/strict-schema-validation-ledger.md`) with one row per acceptance
criterion below, each with a grep/test-verifiable Verify command, per
`priv/ai/LEDGER_DISCIPLINE.md`. Work against the ledger; raise an amendment for any row
that's wrong or impossible; iteration cap 5; closing report = per-row walk. CDC verifies
independently (re-runs Verify, reads diffs — not summaries).

## Verify (acceptance criteria — turn each into a ledger row)

- `priv/schema/{schema.ts,mcp.schema.json,should-as-must.overlay.json,mcp.strict.schema.json}`
  all exist; `mcp.strict.schema.json` is the merge of the other two.
- `scripts/gen-mcp-schema.sh` regenerates `mcp.strict.schema.json` reproducibly; CI drift
  job asserts `git diff --exit-code` clean after regeneration.
- jesse loads and validates against `mcp.strict.schema.json` on **OTP 25, 26, 27, 28**
  (or an amendment names the exact incompatibility and the chosen remedy).
- `grep -n "validate_inbound\|validate_outbound" src/` shows both wired; inbound at the
  classify boundary, outbound inside `send_response/3` + `send_raw/2` + `send_error/4`.
- A test sends a deliberately malformed outbound payload and asserts the worker crashes /
  the client receives `-32603` and **nothing non-conforming reaches the transport**.
- A test sends a malformed **inbound** request and asserts a `-32600`/`-32602` reply (no
  crash).
- The `task_support => allowed` defect (and every other defect the guard surfaces) is
  fixed at the producer; all gates green; per-module coverage ≥90% including the new
  module.
- The SHOULD ⇒ MUST table is in the ledger with spec citations, including any SHOULD
  deliberately not enforced (with reason).
- All standing gates: `rebar3 compile` zero warnings, `xref`, `eunit`+CT, `dialyzer`,
  coverage — all clean.

## Done when

Every inbound request and every outbound message is validated against the strict MCP
schema generated from `schema.ts` + the SHOULD⇒MUST overlay; a non-conforming payload
can never leave the server silently (it crashes in test, becomes `-32603`+stderr-log in
prod); the `tools/list` payload conforms and Claude Desktop lists tools; the schema
artifact is drift-guarded in CI; the ledger's rows are closed with evidence. Submitted
for CDC sign-off.
