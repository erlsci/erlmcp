# erlmcp 0.6.0 — release checklist

Single source of truth for the remaining steps to tag 0.6.0. The feature work
(M0→M6b) is complete and CDC-signed; the pre-release audit is closed. What remains is
examples, docs, live validation, and the mechanical release. **Do not tag until every
content item below is green.**

Status: ☐ todo · ◐ in progress / staged · ☑ done (CDC-verified)

## Content items (must complete before tag)

1. **☑ Examples rehabilitation** — `examples/` tree onto the 0.6.0 core, in CI, smoke
   tests, broken profiles removed. (`task/0.6.0-examples`, `7903c43`; CDC-verified.)

2. **◐ Examples enhancement** — `examples/README.md` with per-example sections + Claude
   Desktop JSON config; single-invocation stdio launchers; **maximal discoverability**
   (DISC-1/2/3 per example, CI-enforced); server-initiated sampling/elicitation demo.
   Prompt staged: `prompts/examples-enhancement-cc-prompt.md` (run after #1 merges).

3. **☐ Acceptance testing vs Claude Desktop** *(joint: Duncan + CDC)* — configure each
   example, restart Claude Desktop, run the per-example acceptance plan: useful
   `instructions` on connect, all tools findable via `_meta` + directory, chainable via
   `next`, features (tasks/cancel, resources/subscribe, server-initiated
   sampling/elicitation) round-trip. CDC drafts the plan from #2's closing-report config
   blocks. *Open question: does Duncan drive Claude Desktop and report back, or is CDC
   set up to drive it directly (needs desktop/computer-use enabled)?*

4. **☐ Docs re-review for 0.6.0 drift** — re-review every `docs/*.md` against the
   **final** code. M5b's rewrite (`db03e58`) predates the audit cleanup and the examples
   work, so expect drift: the F-05 module split (`erlmcp_pagination` /
   `erlmcp_uri_template` / `erlmcp_instructions` likely unmentioned in
   `architecture.md`/`api-reference.md`), the F-03 `make_transport_id` change, the F-10
   configurable ctx timeout, and the rehabilitated examples. CDC writes the prompt once
   #2/#3 land. *(New — Duncan, 2026-05-24.)*

5. **☐ New howto: `docs/creating-an-mcp-server.md`** — step-by-step build of an MCP
   server on erlmcp, best practices (incl. maximal discoverability — point at the
   enhanced examples), testing locally with Claude Code / Claude Desktop, and production
   deployment. Builds on the enhanced examples (#2) and the acceptance-testing learnings
   (#3), so it comes last. CDC writes the prompt after #3. *(New — Duncan, 2026-05-24.)*

   **Decided approach (Duncan, 2026-05-24):** teach the **OTP release** methodology —
   it's the right way to build a long-running OTP server, and it's a greenfield tutorial
   (the reader builds *their own* release project depending on erlmcp; not a refactor of
   erlmcp's own layout).
   - **rebar3 release tooling** (the `{relx, …}` block + `rebar3 release`/`rebar3 tar`),
     *not* raw relx (notoriously hard to drive directly).
   - **`apps/<name>` umbrella convention** for organizing the project's apps/libs
     (the OTP-standard layout; analogous to Rust's `crates/*`).
   - **`sys.config` bundled in the release** — this is the clean fix for the stdio
     logging bug (logger → `standard_error`, applied at boot, no `-config` flag, no
     racy runtime flip). Use it as the worked example of *why* releases matter.
   - The release `bin/<name>` script (e.g. `foreground`) is the Claude Desktop
     `command`; production notes cover running it under a supervisor (systemd, etc.).

## Mechanical release (after all content items green)

6. **☐ Commit** the accumulated working-tree changes — CDC sign-off lines (M2a/M2b/M3b/
   M4/M5a/M5b/M6a/M6b), the two CLAUDE.md rules (coverage + no-CHANGELOG), the audit
   report sign-off, the M7 backlog, this checklist, and the release notes.
7. **☐ Merge** the open task branches (`task/0.6.0-audit-remediation`, `task/0.6.0-examples`,
   `task/0.6.0-examples-enhance`) → `release/0.6.x`.
8. **☐ Merge** `release/0.6.x` → `main`.
9. **☐ Tag `0.6.0`** + publish the release notes (`RELEASE-NOTES-0.6.0.md`) as the
   GitHub release (the CHANGELOG replacement, per house policy).

## Post-0.6.0

- M7 / post-0.6 backlog: `planning/M7-post-0.6-backlog.md`.
- 0.6.1: first extension (graph-RAG), dogfooding the discoverability/extension surface.
