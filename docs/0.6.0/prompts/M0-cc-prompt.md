# CC Prompt — erlmcp 0.6.0, Milestone M0 (Decide, scaffold, clear the ground)

> This is an imperative brief for **CC** (the implementer). It is self-contained
> on purpose: act on what's written here, and load the linked docs before coding.
> **CDC** (the reviewer) will independently re-run every Verify command and read
> your diffs — not your summary — before M0 is allowed to close.

## Your role and this milestone

You are CC, implementing erlmcp 0.6.0. This task is **M0 only**: clear the dead
code and stand up the architecture skeleton so M1 can build the spine. **No
protocol logic lands in M0.**

## Read before writing any code (in this order)

1. **`docs/0.6.0/milestones/M0-decide-scaffold-clear-ledger.md`** — the M0 ledger.
   This is your definition of done. Read every row; you will report a disposition
   for each.
2. **`LEDGER_DISCIPLINE.md`** (project copy) — the verification protocol you must
   follow.
3. **`docs/0.6.0/planning/phase4-0.6.0-development-plan.md`** — §M0, plus §1
   (principles) and §4 (release strategy).
4. **`docs/0.6.0/planning/phase2-idiomatic-erlmcp.md`** — §3 (supervision tree)
   and §10 (module map): the target architecture.
5. **`docs/0.6.0/planning/phase3-gap-analysis.md`** — what is dead, and why.

House style: the **Inaka Erlang Guidelines + the OTP reference texts** (per the
repo `CLAUDE.md`), until a dedicated erlmcp `SKILL.md` exists.

## Locked decisions (non-negotiable — do not relitigate)

- **JSON = `jsx`, but every JSON access goes through `erlmcp_codec`.** No direct
  `jsx:` calls anywhere else; the library must be swappable behind that one module.
- **Schema validator = `jesse`.**
- **Minimum OTP = 25+.** Do not use features newer than OTP 25 (e.g. no
  `-doc`/EEP-48 attributes — use edoc-style docs).
- **Coverage gate = 90% now, ratcheting to 95% by M5.** Retire `--min_coverage=0`.
- **One way to do a thing: no `_new` modules, ever** (dev plan principle #3).
- **Validate at the edge, crash in the interior** (Phase 2 §5).

## Tasks (each maps to a ledger row; work them in this order)

1. **[M0-1]** Delete `src/erlmcp_transport_stdio_new.erl` and
   `src/erlmcp_server_new.erl`. If either holds logic not present elsewhere that
   M1 will need, do **not** smuggle it into M0 — record it in the row's Notes for
   M1 to re-seat. M0 is deletion only.
2. **[M0-3]** Remove the phantom `erlmcp_client_sup` entry from
   `src/erlmcp.app.src` (≈ line 6).
3. **[M0-4]** Remove dispatch to the nonexistent `erlmcp_transport_tcp_new` /
   `erlmcp_transport_http_new` in `src/erlmcp_transport_sup.erl` (≈ lines 24, 26).
4. **[M0-2]** Resolve the three overlapping server modules toward the single
   `erlmcp_server_session` design. In M0 that means removing `erlmcp_server_new.erl`
   (covered by M0-1) and deciding the disposition of `erlmcp_server.erl` and
   `erlmcp_stdio_server.erl` so no dangling references remain (xref must pass).
   **Do not implement the new session here — that is M1.** If reducing to one
   cannot be done without M1 logic, mark M0-2 `deferred` with re-entry "M1
   `erlmcp_server_session` lands" rather than faking a `done`.
5. **[M0-6]** Stand up the Phase 2 §10 module skeleton as **empty** modules with
   `-behaviour`/`-callback` declarations and `-spec` stubs that compile. No logic.
   The modules (from Phase 2 §10):

   ```
   erlmcp                         (public facade / API)
   erlmcp_app                     (application)
   erlmcp_sup                     (top supervisor)
   erlmcp_session_sup             (simple_one_for_one supervisor)
   erlmcp_transport_sup           (supervisor — already exists; reconcile)
   erlmcp_server_session          (gen_statem)
   erlmcp_client_session          (gen_statem)
   erlmcp_registry                (gen_server — discovery/binding only)
   erlmcp_json_rpc                (JSON-RPC 2.0 envelope)
   erlmcp_codec                   (JSON wrapper — the only jsx caller)
   erlmcp_model                   (opaque MCP types)
   erlmcp_schema                  (JSON Schema builder + jesse validator)
   erlmcp_capabilities            (capability + version negotiation)
   erlmcp_ctx                     (request context: progress/cancel/_meta/peer)
   erlmcp_server_handler          (behaviour)
   erlmcp_transport               (behaviour)
   erlmcp_transport_stdio         (gen_server + erlmcp_transport)
   erlmcp_transport_tcp           (gen_server + erlmcp_transport)
   erlmcp_transport_http          (gen_server + erlmcp_transport)
   erlmcp_transport_streamable_http (gen_server + erlmcp_transport)
   erlmcp_sampling / erlmcp_roots / erlmcp_elicitation (behaviours)
   erlmcp_task_sup / erlmcp_task  (supervisor / proc)
   erlmcp_conformance             (CT harness)
   ```

   See the **scope note** below on how much of this list M0 scaffolds — confirm
   with CDC before starting if unsure.
6. **[M0-7]** Create a `docs/0.6.0/MIGRATION-0.5-to-0.6.md` stub (filled in later
   as the `erlmcp` facade solidifies).
7. **[M0-10]** Find `--min_coverage=0` (likely in the `Makefile` or
   `.github/`), remove it, and configure a real ≥90% coverage gate.
8. **[M0-8 / M0-9 / M0-11]** Make `rebar3 compile` warning-clean, `rebar3 xref`
   clean, and CI green on the branch.

## Working protocol

- **Branch:** `0.6.0-m0`.
- **Commit per ledger row** (or per coherent group). In the *same* commit that
  closes a row, update that row's `Status` → `done` and fill `Evidence` (commit
  SHA + the Verify command's output).
- **Raise, don't route around.** If a criterion is wrong, impossible, or needs M1
  logic, raise it as an amendment (ledger Notes + flag to CDC). Never silently
  work around a row.
- **Closing report = a per-row walk.** State a final disposition for **every one
  of the 11 rows**: `done` + evidence, `deferred` + reason + re-entry condition,
  or `no-op` + rationale. No prose summary. Never write "deviations: none." Name
  any uncertainty ("done, but I'm unsure the evidence covers X").
- **Iteration cap: 5.** If you reach iteration 5 without convergence, stop and
  escalate rather than iterating a sixth time.
- **Subagents for lookup only** (find/grep/read), never for implementation or
  judgment, per the repo subagent-delegation policy.

## Out of scope for M0 (do NOT do)

No `gen_statem` session logic, no per-request workers, no transport
implementations, no JSON-RPC envelope logic, no capability negotiation, no feature
surface. Those are M1+. M0 = dead-code removal + empty compiling skeleton +
coverage gate, nothing more.

## Done when

All 11 ledger rows have a final status; `rebar3 compile`/`xref`/`eunit` and CI are
green; the closed ledger is submitted for CDC review.

---

### Scope note for CDC (resolve before handing this to CC)

**Open question:** does M0-6 scaffold the *entire* §10 map as empty stubs (the
literal reading of "stand up the new module skeleton from Phase 2 §10"), or only
the M1-core modules, with M4 transports (`_tcp`/`_http`/`_streamable_http`), M6
tasks (`_task_sup`/`_task`), and the M5 `erlmcp_conformance` harness scaffolded in
their own milestones? Full-map gives maximum architectural visibility and one
clean xref pass over the real shape; core-only keeps M0 smaller and avoids empty
stubs sitting unused for several milestones. **PM lean: full §10 map as empty
stubs** (matches the dev plan wording and the "architecture visible before logic"
goal). Confirm before CC starts; the M0-6 row and this task list update to match.
