# CC Prompt — erlmcp 0.6.0 pre-release code-quality audit

> Imperative brief. This **rides the house audit driver**
> (`collaboration-framework/docs/CODE-AUDIT.md`) — do not reinvent its procedure,
> stance, severity tiers, output format, or "things I looked for and did not find"
> discipline. This overlay adds the **erlmcp-specific targeting** the generic driver
> can't carry, and a **release go/no-go** the driver doesn't produce. Diagnosis only —
> **do not modify code** (the driver says this too; it holds).

## Base procedure — follow CODE-AUDIT.md as written

Run the house Code Audit against this project. In particular, honor its:

- **Preparation** — capture `date +%Y.%m.%d`; read `README.md` + `CLAUDE.md` + the
  current architecture doc; detect languages. Here that resolves to **one language:
  Erlang** (`.erl`). Load the **full** house Erlang knowledge set before auditing —
  `priv/ai/erlang/SKILL.md` and every file under `priv/ai/erlang/guides/`, with the
  **anti-patterns guide as the canonical hunt list** — plus
  `docs/0.6.0/planning/phase0-erlang-rubric.md`.
- **Severity tiers** — Blocker / High / Medium / Low, exactly as the driver defines
  them. *Severity is a commitment; don't use Medium as a hedge.*
- **Stance** — don't soft-pedal; "passing tests is not evidence of correctness"; no
  generic advice (every finding lands on a `file:line`).
- **Output** — the house location/format: `workbench/<DATE>-audit-results-erlang.md`
  plus `workbench/<DATE>-audit-index.md`, with the per-language report structure
  (executive summary → findings by category → per-finding shape → cross-cutting →
  **"things I looked for and did not find," ≥5 clean checks**).
- **Cross-language hunt list** — apply every item; the ones that bite hardest in
  Erlang/OTP: silently dropped errors (`{error,_}` swallowed, bare `catch`), exceptions
  on a library path a caller can reach that should be `{error,_}`, **wildcard/catch-all
  clauses** (`_ -> ...`, `handle_info(_, …)`) that hide non-exhaustiveness, mocks that
  diverge from production paths, resource leaks (unflushed monitors, un-demonitored
  refs, sockets/ports not closed on error paths, timers not cancelled), and
  encoding/line-ending assumptions.

## erlmcp overlay — additions to the per-language hunt list

On top of the anti-patterns guide, **explicitly hunt these project invariants** (from
`CLAUDE.md` → Locked decisions) and grep the tree for each:

- JSON only via `erlmcp_codec` (no `jsx:` elsewhere); `jesse` validation at the session
  boundary, not in the interior.
- **No shared records across module boundaries / in exported specs**; opaque types +
  accessors at boundaries — verify `erlmcp_model` (and peers) aren't bypassed by raw
  maps/records leaking across modules.
- **No boolean parameters** (tagged atoms/tuples instead); no macros for logic; no
  `_new` forks ("one way to do a thing").
- **Validate at the edge, crash in the interior** — flag interior code that
  over-defends with `try/catch` / `{error,_}` plumbing, and edges that *don't* validate.
- Crash-to-JSON-RPC translation applied **uniformly** at the session↔worker boundary.

## erlmcp overlay — known hotspots to audit hardest (from the CDC record)

These passed their milestones; audit them anyway on idiom/design grounds:

1. **`erlmcp_server_session` (1329 LOC)** — the god-module. Cohesion / single
   responsibility: should the per-feature handlers (tools/resources/prompts/logging/
   completion/tasks/batch) be extracted behind the FSM? Cite the house rule on module
   size/responsibility.
2. **Dual `cast`/`info` `{transport_data,_}` handling** (both sessions) — two entry
   points to one handler; idiomatic or a smell?
3. **Task handler arity-2/arity-3 dual dispatch** (`erlmcp_task`, M6a) — flexibility vs.
   magic; is it clear + documented?
4. **Synchronous batch dispatch** in the session process (`handle_batch`, M6b) — does it
   block the FSM vs. the per-request-worker idiom used elsewhere?
5. **`request_peer/3` blocking `receive` (30s)** in the server worker (M3b) — check
   against the house guidance on blocking receives/timeouts.
6. **`_meta` key juggling** (`progressToken`/`_task` exclusion, M6b) — magic-binary
   smells, clarity.
7. **Opaque-type discipline** — do raw maps/records leak across boundaries despite M1-3?
8. **Error-handling consistency** — let-it-crash vs. defensive interior, applied
   uniformly?

**Dead-code hunt (emphasis):** any unreachable/unused export is a finding — to *delete*,
not amend. Dead code has masked real bugs twice in this repo (`start_child/2`; the
supervision bugs behind it). Treat it as Blocker/High when it's an exported, reachable-
looking function that would crash or mislead.

## erlmcp overlay — add a release recommendation

The generic driver isn't release-oriented; this audit is. After the index, add a
**0.6.0 go/no-go**: "clean to tag," or "must-fix before tag: <list of Blocker/High
findings>." Map severities to the gate — **Blocker/High → fix before tagging 0.6.0;
Medium → fix now if cheap, else → `M7-post-0.6-backlog.md`; Low → M7 polish.**

## Done when

The house audit procedure has run for Erlang against the full knowledge set; the
`workbench/<DATE>-audit-results-erlang.md` report + index exist in the house format
(including the ≥5 "did not find" checks); the erlmcp invariants + hotspots were each
explicitly checked; a 0.6.0 go/no-go recommendation is appended; no source files were
modified. Submitted for CDC review (CDC spot-checks findings against the cited
rules/anti-patterns and sanity-checks the severities + the go/no-go).
