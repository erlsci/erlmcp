# CC Prompt — erlmcp 0.6.0, Phase 6 / Milestone P6-M5 (Strict payload validation)

> Imperative brief for **CC**. Self-contained; load the linked docs before coding.
> **CDC** re-runs the ledger's Verify commands and reads your diffs — not your
> summary — before P6-M5 closes. This milestone locks down MCP-schema conformance
> at the **same shared edge** for both transports: M2 (stdio) and M4 (HTTP) now
> hand off to one session core + one responder seam, so the validation lands in
> *one place* and protects both.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **P6-M5 only**: generate a
JSON Schema from `schema.ts`, apply a hand-curated SHOULD⇒MUST overlay (Icon,
`taskSupport`, etc.), wire `jesse` **inbound** (→ `-32600`/`-32602`) and
**outbound** (**fail closed**), add regression tests for the three bugs that
started the whole arc, add a CI schema drift-guard. The example servers (M6)
and the howto's "validation at the edge" section (M7) are not your concern.
**Per-tool `inputSchema` validation on `tools/call`** (validating a tool call's
params against the tool's *registered* inputSchema, distinct from the protocol
schema) is **also out of scope** unless trivial — escalate if uncertain.

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/phase6-m5-strict-validation-ledger.md`** — the P6-M5
   ledger (rows P6M5-1…P6M5-15). Your definition of done.
2. **`priv/ai/LEDGER_DISCIPLINE.md`** — the verification protocol.
3. **`docs/0.6.0/planning/phase6-unified-transport-architecture.md`** —
   re-read §3 (the spine), particularly the bit about validation living at the
   session edge (the chokepoint between `decode_and_classify` and dispatch on
   inbound, and `erlmcp_codec:encode` / `erlmcp_reply:send` on outbound).
4. **`docs/0.6.0/planning/schema.ts`** — the source-of-truth MCP protocol
   schema (2025-11-25). You generate the JSON Schema from this.
5. **The handoff doc — `workbench/2026-05-25-cdc-handoff.md` §1.3 / §1.4 / §1.5
   and §2.** §1.3 (Icon shape), §1.4 (UTF-8 truncation), §1.5 (`taskSupport`
   enum) are the three bugs you write regression tests for. §2 is the original
   brief this milestone fulfils.
6. **`CLAUDE.md`** — especially *Never loosen a check to make it pass* and the
   coverage rule. **House style:** `priv/ai/erlang/SKILL.md` first
   (`11-anti-patterns.md`, then `03-error-handling.md` for fail-closed semantics
   and `04-data-and-types.md` for opaque/precise types around the schema).

## Locked decisions (non-negotiable)

- JSON via `jsx` inside `erlmcp_codec` only.
- **Schema validator = `jesse`** — locked, **not swappable**.
- Min OTP 25+. Dialyzer is gated to OTP 27+ — run `make dialyzer` on **27 and 28**.
- Coverage 90% per-module, scoped via `cover_excl_mods`; **settle the M5 scope in
  your first commit** (P6M5-13).
- Validate at the edge; **crash in the interior**; translate at the boundary.
- **Never loosen a check to reach green** — no suppressions, no widened specs,
  no skipped tests. Escalate, don't loosen. jesse callback signature trips
  strict-mode dialyzer → escalate, don't suppress.

## The known risk — handle this FIRST (P6M5-3)

**`jesse` is draft-04/06; `ts-json-schema-generator` (the most likely source
from `schema.ts`) emits draft-07 with `const` / `anyOf`.** This may not digest
cleanly. **Land P6M5-3 first** — generate a schema, point jesse at it, see what
happens on OTP 25, 26, 27, 28. If it digests cleanly, the rest of the milestone
proceeds normally. If it doesn't, **stop and escalate** with specifics:

- Which schema fragments trip jesse?
- Which `const` / `anyOf` constructs are involved?
- Cross-OTP behaviour (does only one version fail, or all)?

**Do not swap jesse** (locked decision). Sanctioned mitigations include: a small
lowering shim (`const X` → `enum [X]`, etc.), hand-curated draft-04 fragments
for the tripping sections only, or selecting a different generator that emits
draft-04/06 from `schema.ts`. CDC + Duncan choose which. **Do not pick the
mitigation unilaterally** — that is the row's amendment, and it needs sign-off.

## Tasks (each maps to ledger rows; suggested build order)

**Phase A — schema generation + jesse digestion (the risk row).**
1. **[P6M5-1]** Generate a JSON Schema from `docs/0.6.0/planning/schema.ts`. Pin
   the generator + version. Check the generated schema into the repo at a stable
   path (e.g. `priv/schema/mcp-2025-11-25.json`). Add a `make schema` target.
   Document the command in `priv/schema/README.md`.
2. **[P6M5-3]** Wire `jesse` to load the schema; CT `erlmcp_schema_load_SUITE`
   confirms digestion on OTP 25–28. **Escalate immediately if it doesn't** —
   don't push through, don't swap, don't loosen.

**Phase B — overlay.**
3. **[P6M5-2]** Hand-curate the SHOULD⇒MUST overlay (e.g.
   `priv/schema/mcp-overlay.json` or a fragment list applied at load). At
   minimum: `Icon.src` required + `additionalProperties: false` on `Icon`;
   `taskSupport` constrained to `forbidden | optional | required`. **Document
   each entry with the spec section + the bug it guards against** (handoff §1.3
   for Icon; §1.5 for `taskSupport`).

**Phase C — wire the validators.**
4. **[P6M5-4]** Inbound validation at the session edge — between
   `decode_and_classify` and `handle_operational_message`. Use the existing
   `erlmcp_schema:validate/2` wrapper. Map jesse errors to `-32600` (envelope)
   or `-32602` (params).
5. **[P6M5-5]** Outbound validation at `erlmcp_codec:encode` (or one layer
   inside) — validate the term before `jsx:encode` runs. **Fail closed:** in
   test, surface the failure loudly; in prod, log to stderr and emit `-32603`
   instead of the malformed payload. **Never let malformed bytes reach the wire.**
6. **[P6M5-10]** Confirm `erlmcp_schema:validate/2` is the single entry point —
   no parallel validators, no forks.

**Phase D — regressions (the three bugs that started this).**
7. **[P6M5-6]** Icon regression CT: the buggy `icons => [#{type=>emoji,emoji=>…}]`
   shape is rejected by outbound validation when `tools/list` is emitted; the
   correct `data:`-URI form ships cleanly.
8. **[P6M5-7]** `taskSupport` regression CT: `taskSupport => allowed` is
   rejected; the three valid enum values ship cleanly.
9. **[P6M5-8]** UTF-8 well-formedness regression CT: a tool result with a binary
   carrying a lone `0xB0` (the original `°C` truncation) is caught by the M1
   UTF-8 guard, which sits *alongside* jesse (jesse checks decoded shape; UTF-8
   check validates encoded bytes — both needed).

**Phase E — CI drift-guard.**
10. **[P6M5-9]** Add a CI step that regenerates the schema from `schema.ts` and
    asserts byte-for-byte equality with the checked-in artifact. Drift fails CI.
    Standard `actions/setup-node` works.

**Phase F — parity + gates.**
11. **[P6M5-11]** Both transports green under validation — all M2 stdio CTs +
    all M4 HTTP CTs continue to pass. The session core stays unchanged.
12. **[P6M5-12, P6M5-13, P6M5-14, P6M5-15]** `make check` green; coverage gate
    with `erlmcp_schema`, the inbound chokepoint, and `erlmcp_codec` each ≥90%
    per-module; `make dialyzer` clean on 27 and 28 with zero suppressions; CI
    green on `task/0.6.0-p6m5`.

## Working protocol

- **Branch:** `task/0.6.0-p6m5`, cut from `release/0.6.x` **after P6-M4 merges**;
  PR back into `release/0.6.x`.
- **Commit per phase** (schema + digestion → overlay → inbound → outbound →
  regressions → drift-guard → gates); update Status/Evidence per row in the
  closing commit.
- **Raise, don't route around.** jesse-digestion failure → escalate with
  specifics (P6M5-3 is built to handle this). Wrong/impossible criterion →
  amendment with re-entry. Dialyzer warning that looks wrong → escalate
  `file:line`; never loosen.
- **Closing report:** **per-row walk over all 15 rows.** No prose summary. Name
  uncertainty. **Count the actual rows in the ledger file** before declaring the
  walk complete — recurring lesson.
- **Iteration cap: 5.**
- **Subagents for lookup only.**

## Out of scope for P6-M5 (do NOT build)

- **Per-tool `inputSchema` validation on `tools/call`** — distinct from
  protocol-schema validation (uses each registered tool's own schema, not
  `schema.ts`). May ride to P6-M6 or its own follow-up. Escalate if you find
  yourself drifting into it.
- **Example servers exposing validation behaviour** as a user-visible feature —
  **P6-M6**.
- **The "validation at the edge" section in the howto** — **P6-M7**.
- **Swapping jesse** — locked. If it can't digest, escalate (see the risk
  section above).
- **Touching the session core, `erlmcp_server`, the stdio transport, or the
  HTTP transport** — these are M1/M2/M4 work. The new code lives at the codec /
  schema / session-edge chokepoints; if a P6-M5 requirement seems to need the
  spine touched, **escalate** before touching.

## Done when

All 15 ledger rows have a final Status + Evidence; the schema is generated from
`schema.ts`; the overlay tightens Icon + `taskSupport` + any other discovered
MUSTs; jesse validates both inbound and outbound, fail-closed; the three
original-bug regression CTs pass; CI has a drift-guard; both transports stay
green; `make check` green; dialyzer clean on 27 and 28 with zero suppressions;
CI green; the closed ledger is submitted for CDC review.
