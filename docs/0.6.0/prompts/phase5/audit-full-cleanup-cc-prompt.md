# CC Prompt — erlmcp 0.6.0 full audit cleanup (pristine-release pass)

> Imperative brief. Owner directive: **every open audit finding is now MUST-fix before
> tagging 0.6.0** — all the audit's SHOULDs are elevated to MUSTs; nothing defers to M7.
> This closes the remaining 11 findings from `workbench/2026.05.24-audit-results-erlang.md`
> **plus** the F-09 regression test CDC flagged. Continue on
> `task/0.6.0-audit-remediation` (off `release/0.6.x`). **CDC re-verifies every diff
> before the tag — especially F-05.**

## Scope note (what this does and does not include)

- **In scope (MUST):** all 11 open audit findings — F-02, F-03, F-05, F-06, F-07, F-08,
  F-10, F-12, F-13, F-14, F-15 — and the F-09 regression test. Original severities are
  kept only for context; all are mandatory before tag.
- **Out of scope (roadmap, not defects):** the M7 *feature* items — OAuth, distributed
  registry, telemetry (Cluster A) — and the two enhancement-class items (concurrent
  batch dispatch, `request_peer` peer-death fast-fail, Cluster B). These are net-new or
  "correct-but-enhanceable," not "not-100%-right" quality residue. Leave them in M7. If
  in doubt, raise it — do not pull feature work into this cleanup.

## Phase 1 — close the F-09 gap (regression test)

The F-09 fix (batched responses routing through `apply_outbound_response/3`) is correct
but **untested**. MUST add a CT (e.g. in `erlmcp_m6b_SUITE`): a batch containing a
`{response, Id, _}` whose `Id` is a live `out_pending` entry → the entry is removed
(no leak) and the waiting `request_peer` caller is answered. Assert both. This also
covers `apply_outbound_response/3`'s found-branch (otherwise untested new code).

## Phase 2 — dead-code removal (verify zero refs, then delete)

For each, MUST `grep` to confirm zero references, then delete; re-run gates after.

- **F-07** — `src/erlmcp_registry.erl:8-14`: delete the dead `#mcp_capability{}` /
  `#mcp_server_capabilities{}` records; the registry is map-based — align it.
- **F-08** — `src/erlmcp_sup.erl:67-79`: delete the dead legacy stubs
  `start_stdio_server/0,1` and `stop_stdio_server/0` (and their exports).
- **F-06** — `include/erlmcp.hrl:59-143`: remove the ~80 unused macros
  (`?MCP_METHOD_*`, `?MCP_CAPABILITY_*`, `?MCP_FEATURE_*`, `?MCP_CONTENT_TYPE_*`,
  `?MCP_ROLE_*`, `?MCP_MIME_*`, `?MCP_INFO_*`, `?MCP_FIELD_*`, `?MCP_PARAM_*`).
  Confirm each is truly unused before deleting — `grep` per macro/group; if any is
  used, keep that one and note it.

## Phase 3 — small correctness / idiom fixes

- **F-02** — `src/erlmcp_codec.erl:20-21`: replace the blanket `catch _:_` in `decode/1`
  with a specific `catch error:badarg`, matching `encode/1`. Don't swallow unexpected
  classes.
- **F-03** — `src/erlmcp.erl:273,282,291`: `list_to_atom/1` on the transport ID in the
  `start_*_setup` helpers risks atom-table growth. Prefer the structural fix (don't
  coerce to atom — keep the caller-supplied ID as-is, or accept a binary/tuple). If the
  proper fix ripples into registry/transport-ID typing beyond this pass, **raise it**
  and fall back to the audit's documented-single-use constraint with a guard.
- **F-10** — `src/erlmcp_ctx.erl:53`: make the hardcoded 30s `request_peer` timeout
  configurable via the context map (default 30000); thread it from the ctx.
- **F-12** — `src/erlmcp_server_session.erl:1303-1304`: the double `length/1` in
  pagination — use `lists:split/2` or carry the count instead of scanning twice.
- **F-13** — `src/erlmcp.erl:219`: `group_by_category` uses left-side `++` in a fold —
  prepend and reverse at the end (O(n) not O(n²)).
- **F-14** — `src/erlmcp_sup.erl:11`: replace the `?SERVER` macro alias with `?MODULE`.
- **F-15** — `src/erlmcp_registry.erl`: change single-`%` function-level comments to
  `%%` (house style).

## Phase 4 — F-05: decompose the `server_session` god-module (HIGHEST RISK — isolate)

`src/erlmcp_server_session.erl` is 1329 LOC. MUST extract, at minimum,
`erlmcp_pagination` (the `paginate/2`+`paginate_from/3`+`paginated_result/3` logic),
`erlmcp_uri_template` (the level-1 template matching), and `erlmcp_instructions` (the
`generate_instructions/1`/`build_instructions_text/2` logic) into their own modules,
with `server_session` calling them.

- This is a **pure refactor** — no behavior change. The extracted modules get `-spec`s
  and **must each reach ≥90% coverage** (they were covered inside `server_session`;
  keep them covered standalone). `cover_excl_mods` stays `[]`.
- Do this as its **own commit**, after Phases 1–3 are green, so CDC can review it in
  isolation. Re-run the **full** gate after: compile/xref/eunit/CT/proper/dialyzer/cover,
  the conformance scorecard (still 100%), and confirm no behavior changed.
- **If the extraction destabilizes anything you can't quickly resolve, STOP and raise
  it** — F-05 is the one finding where deferring *only it* to 0.6.1 is an acceptable
  fallback (the others are not). Do not ship a half-done extraction.

## Phase 5 — bookkeeping

- In `workbench/2026.05.24-audit-results-erlang.md`, mark **all** findings resolved (or
  F-05 deferred *only if* the Phase 4 fallback was taken, with reason).
- Remove **Cluster C** from `docs/0.6.0/planning/M7-post-0.6-backlog.md` (now done) —
  unless F-05 fell back, in which case leave only F-05 there. Cluster A and the Cluster B
  enhancements stay.
- Update any ledger evidence touched (e.g. if F-12/F-13 touch already-closed rows, add a
  one-line cleanup note; don't reopen).

## Working protocol

- **Branch:** `task/0.6.0-audit-remediation` (continue); PR into `release/0.6.x`.
- Commit per phase (Phase 4 strictly its own commit). Raise an amendment for F-03 or
  F-05 if they exceed a clean small change.
- Every phase ends green: `rebar3 compile` (zero warnings), `xref`, `eunit`, CT,
  `proper`, `dialyzer`, cover (`cover_excl_mods` `[]`, every module ≥90%).
- Closing report: per-finding disposition (resolved / deferred-with-reason) + the F-09
  test; name any uncertainty.

## Done when

All 11 findings are resolved (or F-05 alone deferred via the stated fallback); the F-09
regression test exists and passes; dead code is gone; every gate is green with
`cover_excl_mods` empty and all modules ≥90%; the audit report and M7 backlog reflect
the closures. Submitted for CDC sign-off — after which 0.6.0 is pristine to tag.
