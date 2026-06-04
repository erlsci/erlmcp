# MCP Protocol Schema — priv/schema/

## Files

- `mcp-2025-11-25.json` — JSON Schema (draft-06) for MCP protocol 2025-11-25.
  Hand-curated from `docs/0.6.0/planning/schema.ts`. Includes the SHOULD⇒MUST
  overlay (Icon.src required, additionalProperties:false on Icon, taskSupport
  enum constrained).

## Why hand-curated (not generated)

`jesse` 1.8.x supports JSON Schema draft-03, draft-04, and draft-06 only.
The standard TypeScript-to-JSON-Schema generators (`ts-json-schema-generator`,
`typescript-json-schema`) emit draft-07 with `const`, `if`/`then`/`else`, and
`$ref` patterns that jesse cannot digest. Rather than swap jesse (locked
dependency) or maintain a brittle lowering shim, we hand-curate a draft-06
schema derived from `schema.ts` covering the types we actually validate.

This is the sanctioned mitigation recorded in the P6-M5 ledger (P6M5-3
amendment): hand-curated draft-06 fragments for jesse compatibility.

## Derivation source

Every type in `mcp-2025-11-25.json` maps 1:1 to a `schema.ts` interface or
type. The derivation is mechanical (TypeScript types → JSON Schema objects)
with two intentional tightenings documented inline as the SHOULD⇒MUST overlay:

1. **Icon.src required + additionalProperties:false** — guards against the
   original "no tools available" bug (handoff §1.3) where extra fields on Icon
   caused Claude Desktop to silently reject tools.

2. **taskSupport enum: "forbidden" | "optional" | "required"** — guards against
   the original `taskSupport => allowed` bug (handoff §1.5) where an invalid
   enum value was accepted without error.

## Updating

When `schema.ts` changes (new protocol version), update `mcp-2025-11-25.json`
by hand to match. The CI drift-guard (`make schema-check`) verifies that the
checked-in schema is loadable by jesse and covers the expected definitions.
