# Phase 6, Milestone P6-M5: Strict payload validation (jesse at the edge)

> Per-milestone verification ledger (see `priv/ai/LEDGER_DISCIPLINE.md`). CC works
> against this ledger; CDC verifies every disposition independently against the
> actual commit state — running each Verify command and reading diffs, not
> summaries. No milestone advances until the ledger is fully closed.

**Goal (Phase 6 §6, P6-M5):** lock down MCP-schema conformance at the **same edge
for both transports** — now that M2 and M4 share one session core and one
responder seam, the validation work has a single seam to plug into. Generate a
JSON Schema from `docs/0.6.0/planning/schema.ts` (protocol **2025-11-25**); apply
a hand-curated **SHOULD⇒MUST overlay** (Icon.src, additionalProperties on Icon,
the `taskSupport` enum, plus any other tightenings discovered); wire `jesse`
**inbound** (returning `-32600` for envelope errors, `-32602` for param errors)
and **outbound** (**fail closed** — never emit a non-conforming payload); add
regression tests for the three bugs that started the whole arc (Icon shape,
`taskSupport` enum, outbound UTF-8); add a **CI schema drift-guard**; and confirm
both transports stay green under validation.

This is the handoff §2 work, finally landing on a stable shared edge.

**Locked decisions (carried + one known risk):**
- JSON via `jsx` behind `erlmcp_codec` only.
- **Schema validator = `jesse`** (locked). The validator is **not** swappable.
- Min OTP 25+. Dialyzer gated to OTP 27+ — run on **27 and 28**.
- Coverage 90% per-module, scoped via `cover_excl_mods`.
- Validate at the edge, **crash in the interior**; translate at the session↔worker
  boundary. The session's outbound chokepoint (`erlmcp_codec:encode` /
  `erlmcp_reply:send`) is the natural fail-closed point.
- Opaque types + accessors; no shared records; one way to do a thing.
- **Never loosen a check to make it pass** (`CLAUDE.md`): no suppressions, no
  widened specs, no skipped tests — escalate instead.

**Known risk (named upfront, not a surprise):** `jesse` is draft-04/06;
`ts-json-schema-generator` (the most-likely schema source from `schema.ts`)
emits draft-07 with `const` / `anyOf`. **If `jesse` can't digest the generated
schema on OTP 25–28, raise an amendment with specifics** (which schema fragments
trip it, why) — **do not swap `jesse`** (locked decision). Sanctioned mitigations
include a small lowering shim, hand-curated draft-04 fragments for the tripping
sections, or selecting a different generator that emits draft-04/06. CC should
**verify jesse digestion as the first work item** so the risk lands early.

**Branch:** `task/0.6.0-p6m5`, cut from `release/0.6.x` **after P6-M4 merges**.
PR back into `release/0.6.x`. All Verify commands run from the repo root. All
rows start `open`.

## Ledger

| ID | Criterion | Verify | Significance | Origin | Status | Evidence | Notes |
|----|-----------|--------|--------------|--------|--------|----------|-------|
| P6M5-1 | A JSON Schema is **generated** from `docs/0.6.0/planning/schema.ts` (protocol 2025-11-25) and checked into the repo at a stable path (e.g. `priv/mcp_schema.json` or `priv/schema/mcp-2025-11-25.json`). The generator + the exact generation command are documented. | The generated schema file exists and parses as JSON; a `make schema` (or equivalent) target regenerates it; the generation command is recorded in `README.md` or a `priv/schema/README.md`. | serious | handoff §2 (the lead-off requirement) | open | | Pick `ts-json-schema-generator` unless something better is available. Pin the version. The schema file is a generated artifact but is checked in so production builds don't need Node. |
| P6M5-2 | A hand-curated **SHOULD⇒MUST overlay** sits beside the generated schema (e.g. `priv/schema/mcp-overlay.json` or a per-fragment patch list) and is applied at load time. At minimum it tightens: `Icon.src` required + `additionalProperties: false` on `Icon`; `taskSupport` constrained to `forbidden | optional | required`. Each entry is documented with the spec section and the bug it guards against. | The overlay file exists; tests assert specific overlay tightenings are active (the regression rows P6M5-6 / P6M5-7 prove the two named ones); a one-paragraph rationale per overlay entry lives in the overlay file or its README. | serious | handoff §2; the original §1.3 / §1.5 bugs | open | | Keep the overlay small and explicit. Don't over-tighten — each rule needs a documented reason. |
| P6M5-3 | **`jesse` digests the generated+overlay schema on OTP 25, 26, 27, 28.** If draft-07 features (`const`, `anyOf`, etc.) trip jesse, the row is closed by a **named amendment** with the specific tripping fragments + chosen mitigation (lowering shim / hand-curated draft-04 fragments / different generator). **Do not swap jesse.** | `rebar3 ct --suite erlmcp_schema_load_SUITE` (or equivalent) loads the schema cleanly on the matrix; CI proves the multi-OTP case. | serious | Phase 6 §6 risk callout | open | | This is the row to land **first** — the whole milestone's mechanism depends on it. If it doesn't digest, the design changes; better to know on day 1 than week 2. |
| P6M5-4 | **Inbound validation** at the session edge: every JSON-RPC envelope is validated against the schema before dispatch. Envelope errors return JSON-RPC `-32600` (Invalid Request); method-specific param errors return `-32602` (Invalid params). The error response itself is schema-valid. | CT `erlmcp_inbound_validation_SUITE`: malformed envelope → `-32600`; valid envelope with bad params (per the method's schema) → `-32602`; the returned error response passes outbound validation. | serious | handoff §2 | open | | The chokepoint lives between `decode_and_classify` and `handle_operational_message`. Reuse `erlmcp_schema:validate/2` — the jesse wrapper. |
| P6M5-5 | **Outbound validation at the emit boundary** — fail closed. Before `erlmcp_codec:encode` ships a payload, the term is validated against the schema. On failure: the session **never emits the non-conforming payload**. In test, fail loud (crash, surface the failure); in prod, log to stderr and emit `-32603` (Internal error) instead. Whichever mode, **no malformed bytes ever reach the wire**. | CT: a deliberately malformed outbound term (e.g. a tools/list with a tool missing `inputSchema`) is **never delivered to the responder**; in the test profile, it crashes with an identifiable reason; the regression rows P6M5-6 / P6M5-7 / P6M5-8 land on top of this guard. | serious | handoff §2; "validate at edge, crash in interior" | open | | This is the row that protects the wire. The M1 outbound UTF-8 guard (P6M1-9) is the prototype; this generalises it to full schema. |
| P6M5-6 | **Regression: Icon shape.** A tool spec carrying the original buggy `icons => [#{type=>emoji, emoji=>…}]` shape (no `src`, extra fields) is **rejected** by outbound validation when `tools/list` is emitted. The valid `data:`-URI form is **accepted**. | CT: register a tool with the buggy emoji-icon shape → emitting `tools/list` triggers the outbound validator and **fails closed** (no malformed payload, identifiable error); register with `data:`-URI shape → `tools/list` ships cleanly. | serious | handoff §1.3 (the bug that started the whole arc) | open | | The single test that would have caught the original "no tools available" failure on the first day. |
| P6M5-7 | **Regression: `taskSupport` enum.** A tool spec with `taskSupport => allowed` (not in the enum) is **rejected** by outbound validation when `tools/list` is emitted. `forbidden` / `optional` / `required` are accepted. | CT: register tool with `taskSupport => allowed` → `tools/list` fails closed; register with each of the three valid values → ships cleanly. | serious | handoff §1.5 | open | | |
| P6M5-8 | **The M1 outbound UTF-8 guard is preserved and exercised end-to-end.** A tool result whose content carries an ill-formed UTF-8 binary (e.g. `<<16#95>>`, the original `°C` truncation) is caught by the outbound check; no malformed bytes ship. | CT: a tool that returns `<<"30", 16#B0, "C">>` (single 0xB0, ill-formed) is caught by the outbound guard; the `unicode:characters_to_binary/2`-based check in `erlmcp_codec:ensure_utf8` is still in the emit path. | serious | handoff §1.4; preserves P6M1-9 | open | | This guard sits *alongside* jesse — jesse validates the decoded term shape; the UTF-8 check validates the encoded bytes. Both are needed (a jesse-conforming term can still encode to ill-formed UTF-8 if a binary value contains a truncated codepoint). |
| P6M5-9 | **CI schema drift-guard:** a CI step regenerates the JSON Schema from `schema.ts` and asserts byte-for-byte equality with the checked-in copy. Drift fails CI. | `.github/workflows/ci.yml` runs the regeneration; the drift-check job fails red on a deliberate edit to `schema.ts` not accompanied by a regenerated artifact. | serious | handoff §2 | open | | Node is needed for the drift step only (the runtime path uses jesse on the prebuilt schema). Standard `actions/setup-node` works. |
| P6M5-10 | **`jesse` remains the only schema validator** — no fork, no swap, no parallel implementation. `erlmcp_schema:validate/2` is the single entry point used by both inbound and outbound paths. | `! grep -rnE "\\bjsv\\b\|\\bdraft_07\\b\|json_schema_validator" src` (no other validator names); `grep -nE "erlmcp_schema:validate" src/erlmcp_*.erl` shows the two call sites (inbound at session edge, outbound at codec). | serious | Locked decision | open | | |
| P6M5-11 | **Both transports green under strict validation.** All stdio CTs from M2 and all HTTP CTs from M4 pass with the new validators wired in. No `-32600`/`-32602`/`-32603` from the wire unless the test deliberately drove one. | `make check` exits 0 incl. all stdio + HTTP suites; `grep -rn "-32603\|invalid_payload" _build/test/logs/` shows only test-driven cases. | serious | M2/M4 parity; Phase 6 §3 unification mandate | open | | The architectural payoff: one validation seam, two transports, both still green. |
| P6M5-12 | **No regression** on existing tests; `make check` exits 0. | `make check` green; `rebar3 eunit` + `rebar3 ct` 0 failures. | serious | DoD | open | | |
| P6M5-13 | **Coverage** — `erlmcp_schema`, the new inbound-validation chokepoint, and `erlmcp_codec` (now carrying outbound jesse + UTF-8 guards) each ≥90% per-module; `cover_excl_mods` scoping retained (no *new* exclusions). | `rebar3 as test cover -v --min_coverage=90` exits 0; per-module figures recorded in evidence. | serious | Locked decision (coverage) | open | | Pre-spec the scoping in the first commit — the lesson from M1/M2/M4. |
| P6M5-14 | **Dialyzer clean** on OTP 27 **and** 28 under the strict set, **no suppressions**, no widened specs. (Closes with P6M5-15 — 27 retires when CI's 27 leg runs.) | `make dialyzer` clean on 27 and 28; `! grep -rn "nowarn\\|-dialyzer(" src` (no new suppressions). | serious | DoD; `CLAUDE.md` never-loosen rule | open | | jesse's own callbacks should pass strict mode. If a jesse callback signature trips strict, escalate — don't suppress. |
| P6M5-15 | **CI green** on `task/0.6.0-p6m5` across the OTP 25–28 matrix, including the schema drift-guard. | CI workflow passes on the branch. | serious | DoD | open | | The independent reproducer; also confirms the 27 leg of P6M5-14 and the cross-OTP jesse digestion of P6M5-3. |

### Significance legend
`serious` = architectural invariant or DoD gate whose violation undermines the
milestone. `correctness` = a guarantee P6-M5 claims. `polish` = hygiene.

## What Worked

_(Filled in at milestone close.)_

## Carry-forward to P6-M6+

_(Filled in at close — e.g. per-tool `inputSchema` validation on `tools/call`
(potentially a P6-M6 extension if example tools want it); example servers
exposing the validation behaviour as a user-visible feature in their READMEs
(P6-M6); a "validation at the edge" section in the howto (P6-M7). Note any
module still in `cover_excl_mods` with its re-entry milestone.)_

## Closure

_(Open.)_
Closed at commit `<SHA>` on `<date>`. CDC verification: `<name/session>`.
Total rows: 15. Done: `<n>`. Deferred: `<n>`. No-op: `<n>`.
