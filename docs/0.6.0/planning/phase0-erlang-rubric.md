# Phase 0 — Idiomatic Erlang/OTP Rubric (erlmcp 0.6.0)

A distilled, citable rubric of house-style Erlang/OTP conventions. Hold the MCP SDK design
against these rules. Each rule is one line + rationale + source citation.

**Sources read:**
- **Inaka** = `erlang-guidelines/README.md` (Inaka Erlang Coding Standards). Read in full. PRIMARY.
- **nuex** = `nuex-style-guide/` — **empty** (only `.gitkeep`); no rules available. Not citable.
- **PE** = *Programming Erlang* (Armstrong) — skimmed for error handling / OTP.
- **DSE** = *Designing for Scalability with Erlang/OTP* (Cesarini & Vinoski) — skimmed for behaviours / supervisors / applications.
- **LYSE** = *Learn You Some Erlang* — skimmed for FSM / OTP / testing.

Citation format inline: `(Inaka: Rule Heading)`, `(PE: Section)`, `(DSE: Chapter)`, `(LYSE: Chapter)`.

> Note: the reference texts predate `gen_statem` (they describe `gen_fsm`). Treat their FSM
> guidance as conceptual; map it onto `gen_statem` in modern code.

---

## 1. MODULE & PROJECT STRUCTURE

- **No God modules.** Each module does one thing; one responsibility done well. A module that
  accretes unrelated functions (e.g. all DB ops for users+posts+comments) is rejectable.
  Rationale: small single-purpose modules are easy to reason about and maintain. *(Inaka: No God modules)*
- **Keep functions small (~12 expressions).** A function should do one thing; refactor large
  ones into named helpers. Rationale: readability, testability, reuse, fits on a screen. *(Inaka: Keep functions small)*
- **More, smaller functions over case expressions.** Prefer function-clause pattern matching to a
  top-level/huge `case`; each clause gets a meaningful name. Rationale: a `case` is an anonymous
  function obscuring meaning. *(Inaka: More, smaller functions over case expressions)*
- **Group functions logically.** Exported functions first, then a private-functions section.
  Rationale: well-structured code is easier to read/modify. *(Inaka: Group functions logically)*
- **Types go first; records go first.** Place all `-type`/`-record` definitions at the top of the
  module, before function bodies. Rationale: matches edoc ordering; types/records are shared by
  many functions. *(Inaka: Get your types together; Records go first)*
- **Group modules in subdirectories by functionality.** Use descriptive "package" subdirs when
  there are many modules. Rationale: easier to find and understand modules. *(Inaka: Group modules in subdirectories by functionality)*
- **Header files: no types, no records, no functions.** `.hrl` MAY hold macro defs only (and
  macros are discouraged). Rationale: sharing records/types via headers couples modules and breaks
  encapsulation. *(Inaka: Header files; No types in include files; No nested header inclusion)*
- **No nested header inclusion** without `-ifndef(...)` guards. Rationale: avoids duplicate
  inclusion / ordering conflicts. *(Inaka: No nested header inclusion)*
- **Honor DRY.** Don't duplicate code or re-implement something that already exists. Rationale:
  rejectable in review. *(Inaka: Honor DRY)*
- **Application directory structure: `ebin/ src/ priv/ include/`.** `src` holds Erlang source +
  private includes; `priv` holds non-Erlang assets. Rationale: tools and release handling depend on
  this layout. *(DSE: Applications)*

**Naming:**
- **Variables CamelCase; atoms/functions/modules lowercase_with_underscores.** Don't mix.
  Rationale: distinguishes variables from atoms; matches OTP. *(Inaka: Variable Names; Function Names; Lowercase atoms; CamelCase over Under_Score)*
- **One module-naming convention** (e.g. `erlmcp_*` prefix everywhere, not mixed). Rationale:
  coherence. *(Inaka: Stick to one convention for naming modules)*
- **Be consistent naming concepts** — same variable name for the same concept across modules
  (greppable). Rationale: easy to find all uses. *(Inaka: Be consistent when naming concepts)*
- **Prefer shorter but meaningful names** (`OrgID` not `OrganizationToken`). *(Inaka: Prefer shorter variable names)*
- **Don't use `_Ignored` variables.** If prefixed with `_`, don't read it. *(Inaka: Don't use _Ignored variables)*
- **Comment levels: `%%%` module, `%%` function, `%` inline.** *(Inaka: Comment levels)*

---

## 2. TYPES & SPECS

- **Write `-spec` for all exported functions** (and unexported ones when it documents real value);
  define as many named types as needed. Rationale: better Dialyzer output; documents intent. *(Inaka: Write function specs)*
- **Export custom types used in exported functions** via `-export_type`, defining them with
  `-type`/`-opaque`. Rationale: documentation + encapsulation. *(Inaka: Types in exported functions)*
- **Types live in the module that owns the data, never in `.hrl`.** Reference cross-module as
  `some_mod:some_type()` (module namespacing). Rationale: avoids type-name clashes; enables
  `-opaque`. *(Inaka: No types in include files)*
- **Always type record fields** (`field :: type()`), never bare `field`. Rationale: field types are
  core to the data definition. *(Inaka: Types in records)*
- **Avoid records in specs — use types.** Define `-opaque foo() :: #foo{}` and spec with `foo()`,
  not `#foo{}`. Rationale: types export, aiding docs + encapsulation. *(Inaka: Avoid records in specs)*
- **Don't share records across modules.** Expose an exported `-opaque` type + accessor functions
  instead of a shared `.hrl` record. Rationale: hides structure, aids encapsulation; structural
  changes stay internal. *(Inaka: Don't share your records)*
- **Name OTP state `#mod_state{}` with `-type state() :: #mod_state{}`.** Rationale: recognizable in
  debug dumps; Dialyzer detects state leaks. *(Inaka: Explicit state should be explicitly named)*
- **Records/field names** are atoms: lowercase_with_underscores. *(Inaka: Record names)*

---

## 3. BEHAVIOURS & OTP

- **Use `-callback` attributes, not `behaviour_info/1`.** Rationale: avoids deprecated form (R14+).
  *(Inaka: Use -callback attributes over behaviour_info/1)*
- **Encapsulate reusable code in behaviours.** Define extension points with `-callback`. Rationale:
  "the OTP way" — split generic (behaviour module) from specific (callback module) code via a
  contract on callback names/types/returns. *(Inaka: Use behaviours; DSE: Behaviors — Callback Modules)*
- **Encapsulate OTP server APIs.** Never make raw `gen_server:call/cast` (or `gen_statem` events)
  across module boundaries; wrap each in an API function in the same module that implements the
  matching `handle_*`. Rationale: easy to find call sites; can change message format or even swap
  behaviour type without touching callers; better Dialyzer coverage. *(Inaka: Encapsulate OTP server APIs)*
- **gen_server = client-server / request-reply** with state; the canonical pattern (init / handle /
  terminate lifecycle). *(DSE: Behaviors — Process Skeletons)*
- **gen_statem (modern gen_fsm) = explicit protocol state machines** — when behavior depends on a
  finite set of named states with event-driven transitions (e.g. a transport handshake / connection
  lifecycle). Rationale: an FSM "represents complex procedures and sequences of events" clearly;
  states force transitions on events. *(LYSE: Rage Against the Finite-State Machines)*
- **Supervisors only supervise.** A supervisor's only task is to monitor/restart children; put no
  business logic in it. Rationale: deterministic, well-tested restart/race handling, simpler
  workers. *(DSE: Supervisors — Supervision Trees)*
- **Build supervision trees** (supervisors = nodes, workers = leaves); supervisors trap exits and
  take corrective action. Push error recovery into the tree, not into worker code. *(DSE: Supervisors)*
- **Startup is not allowed to fail.** If a supervisor can't start a child it aborts startup ("we
  draw the line at startup failures"); a failed app start shuts the node down. Rationale: nothing
  abnormal should happen at boot. *(DSE: Supervisors; DSE: Applications — How Applications Run)*
- **Normal vs library application.** Normal app starts a top-level supervisor + tree; library app is
  just modules (no supervisor/processes). Rationale: choose deliberately for an SDK — the client/
  server roles are normal apps, pure helpers may be library apps. *(DSE: Applications)*
- **Move self-contained, reusable functionality into independent applications.** Rationale: easier
  sharing; consider open-sourcing. (But don't make highly project-coupled libs.) *(Inaka: Move stuff to independent applications)*

---

## 4. ERROR HANDLING

- **Let it crash.** Write the happy path with minimal defensive code; assume args are correct; let
  the process die and let a supervisor/another process correct it. Rationale: clean separation of
  problem-solving code from error-correcting code; dramatic code reduction. *(PE: Error Handling Philosophy — Let It Crash)*
- **Let some other process fix the error.** Detect failures remotely via links/monitors + supervision;
  don't intertwine recovery with logic. *(PE: Error Handling Philosophy — Let Some Other Process Fix the Error)*
- **Crash early / fail fast.** Flag the first place an error occurs; don't compute further after
  things go wrong (better diagnostics, don't make matters worse). *(PE: Why Crash?)*
- **Don't hand-roll error-recovery in workers.** Speculative defensive recovery code adds complexity
  and bugs while handling only a fraction of cases; let the supervisor behaviour handle the
  unexpected. *(DSE: Supervisors — intro)*
- **When you must program defensively, do it on the client/outermost layer.** Validate input in the
  API function (guard the function head) so the caller crashes on bad input rather than the
  gen_server — avoids a wasted roundtrip and a server crash. Rationale: choose where you crash. *(Inaka: When programming defensively, do so on client side)*
- **Loud errors.** Even when you handle/catch an error, log it with a stack trace so watchers can
  understand what happened. *(Inaka: Loud errors)*
- **Use `try ... of ... catch`, not `case catch`.** Keep the golden path separate from error
  handling. *(Inaka: Don't use case catch)*
- **Don't nest `try...catch`.** One flat catch with multiple clauses; nesting defeats the purpose. *(Inaka: Avoid nested try...catches)*
- **Avoid non-local returns (`throw`/`catch`).** `throw` is "returning via side effects"; prefer
  tail recursion. Reserve only for breaking out of deep recursion, rarely. *(Inaka: Avoid non-local returns)*
- **Logging levels** carry meaning: debug/info/notice/warning/error(+stack trace)/critical. *(Inaka: Properly use logging levels)*

---

## 5. API & FUNCTION DESIGN

- **Use the facade pattern on libraries.** Expose a single, curated module of the basic-use
  functions — not a dump of every exported function. Rationale: lowers learning curve; self-
  documenting; makes the lib tempting to use. *(Inaka: Use the facade pattern on libraries)*
- **Avoid boolean parameters** for clause selection; use descriptive atoms (`full`/`empty`, not
  `true`/`false`). Rationale: intent is clear without reading the function body. *(Inaka: Avoid boolean parameters)*
- **Use atoms or tagged tuples for messages** — a human-readable atom in element 1 of any tuple
  (including `gen_server:call/cast` payloads). Rationale: clarity, fewer confused-message bugs,
  debuggable mailboxes. *(Inaka: Use atoms or tagged tuples for messages)*
- **Avoid dynamic calls** (`Mod:Fun(...)` with variable Mod/Fun) unless genuinely needed. Rationale:
  `xref` can't check them. *(Inaka: Avoid dynamic calls)* — *Tension point for a plugin/transport
  registry: see §8.*
- **Don't write spaghetti** — no list comprehensions wrapping a `case`, no `begin/end` blocks of
  nested logic; the call graph should be a DAG. *(Inaka: Don't write spaghetti code)*
- **Avoid deep nesting (max ~3 levels).** Refactor into named functions. *(Inaka: Avoid deep nesting)*
- **Avoid `if`.** Use `case` or (better) function-clause pattern matching. *(Inaka: Avoid if expressions)*
- **Prefer pattern matching over equality tests** (`=:=` + boolean switch). *(Inaka: Prefer pattern-matching over testing for equality)*
- **Prefer pattern matching over `length/1`** (e.g. `f([])` vs `f([_|_])`). *(Inaka: Avoid unnecessary calls to length/1)*
- **Favor higher-order functions (fold/map/comprehension) over manual recursion.** Rationale: safer,
  more comprehensible; a buggy recursion can take down a node. *(Inaka: Favor higher-order functions over manual use of recursion)*

---

## 6. SYNTAX & STYLE

- **Spaces over tabs, 2-space indentation.** *(Inaka: Spaces over tabs)*
- **100 columns max per line.** *(Inaka: 100 column per line)*
- **Surround operators and commas with spaces.** *(Inaka: Use your spacebar)*
- **No trailing whitespace.** *(Inaka: No Trailing Whitespace)*
- **Maintain existing style** when editing others' modules / a project-wide style. *(Inaka: Maintain existing style)*
- **No macros**, except predefined (`?MODULE`, `?MODULE_STRING`, `?LINE`) and literal constants
  (`?DEFAULT_TIMEOUT`, `?HTTP_CREATED`). Use functions for repeated code. Rationale: macros make
  debugging harder. *(Inaka: No Macros)*
- **Macros, when used, are ALL_UPPER_CASE.** *(Inaka: Uppercase macros)*
- **No macros for module or function names** (e.g. `?SERVER`, `?MODULE` aliasing). Rationale: breaks
  copy-paste-into-shell debugging. *(Inaka: No module or function name macros)*
- **IOLists over string concatenation** (`["Hello ", Param, "!"]` not `"Hello " ++ ...`). Rationale:
  performance, fewer conversion errors. *(Inaka: IOLists over string concatenation)*
- **Don't `-import`.** Always qualify external calls as `mod:fun`. Rationale: distinguishes
  local/external; module is part of the meaning. *(Inaka: Don't import)*
- **Don't `-compile(export_all)`.** Export only the documented public API. Rationale: encapsulation;
  enables aggressive internal refactoring. *(Inaka: Don't export_all)*
- **No debug calls** (`io:format`, `ct:pal`, debug-only logging) in `src/` production code. *(Inaka: No debug calls)*

---

## 7. TESTING

- **Simple unit tests: 1–2 asserts per test, single responsibility.** Rationale: multiple small
  tests surface multiple errors in one run; one giant test forces fix-one-at-a-time. *(Inaka: Simple unit tests)*
- **EUnit for white-box / module-level unit tests** — simple and fast; the default for unit work.
  *(LYSE: EUnited Nations Council; LYSE: Common Test for Uncommon Tests — "EUnit is pretty good at module level")*
- **Common Test for integration / system testing** and testing across processes or non-Erlang
  software — where EUnit's inter-test coupling breaks down. The bigger/blacker-box the test, the
  more appropriate Common Test. *(LYSE: Common Test for Uncommon Tests)*
- **Property-based testing (PropEr / QuickCheck) to find unexpected failures** you'd never devise by
  hand — generate failure scenarios for protocol/state-machine code. *(DSE: Supervisors — intro)*
- **Test functions are delineated by small functions** (see §1): structure code as small tail-called
  functions to create clear "testing hinge points." *(Inaka: Keep functions small — Notes)*

---

## 8. SDK / LIBRARY-SPECIFIC

- **Facade module is the public API.** For erlmcp, a single `erlmcp` (or `erlmcp_client` /
  `erlmcp_server`) facade exposing the curated basic-use functions; hide the rest. *(Inaka: Use the facade pattern on libraries)*
- **Behaviours are the extension/plug-in mechanism.** Define transports, and the registration
  targets (tools/resources/prompts handlers) as `-callback`-based behaviours — generic SDK code +
  user callback modules under a contract. *(Inaka: Use behaviours; DSE: Behaviors — Callback Modules)*
- **Expose `-opaque` types + accessors for public data** (handles, requests, registry entries) —
  never leak records across the API boundary. *(Inaka: Don't share your records; Types in exported functions)*
- **Encapsulate every OTP interaction behind an API function** so transport/role internals
  (`gen_server` vs `gen_statem`) can change without breaking users. *(Inaka: Encapsulate OTP server APIs)*
- **Roles = normal applications (supervision trees); pure helpers = library applications.** Structure
  client and server as independent OTP applications. *(DSE: Applications)*
- **Validate user input at the API edge** (client-side defensive guards), let internals run on the
  let-it-crash assumption. *(Inaka: When programming defensively, do so on client side; PE: Let It Crash)*

### Tension points with a Rust-style API (call these out in design review)

- **Dispatching over a registry of pluggable transports/handlers** invites *dynamic calls*
  (`Mod:Fun(...)`), which Inaka discourages because `xref` can't check them. *Resolution:* dispatch
  through a **behaviour** with declared `-callback`s (still indirection, but typed/checkable) rather
  than ad-hoc `apply/3`. *(Inaka: Avoid dynamic calls vs Use behaviours)*
- **No bool params** clashes with Rust-style `bool`-flag arguments — use descriptive atoms instead
  (`{mode, streaming}` not `true`). *(Inaka: Avoid boolean parameters)*
- **No records in specs / don't share records** clashes with a Rust struct-passing style — model
  public data as `-opaque` types + accessors, pass via API functions, not exposed structs. *(Inaka:
  Avoid records in specs; Don't share your records)*
- **No macros** clashes with Rust's macro-heavy ergonomics (e.g. derive-like builders). Express the
  same via functions/behaviours; macros only for literal constants. *(Inaka: No Macros)*
- **`-spec`-everything + opaque types** is the Erlang substitute for Rust's compile-time type
  guarantees — lean on Dialyzer, not runtime checks. *(Inaka: Write function specs; Types in exported functions)*
- **Let-it-crash vs Rust `Result<T,E>` everywhere** — at the API edge, error tuples (`{ok, _} |
  {error, _}`) are idiomatic and reasonable; internally, prefer crashing + supervision over
  threading errors through every call. Don't replicate exhaustive `Result` plumbing inside the
  supervision tree. *(PE: Let It Crash; Inaka: When programming defensively, do so on client side)*
