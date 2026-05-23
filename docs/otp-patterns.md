# OTP Patterns in erlmcp

## Supervision Tree

```
erlmcp_sup (one_for_all)
├── erlmcp_registry          (gen_server — discovery only)
├── erlmcp_server_sup        (simple_one_for_one → server sessions)
├── erlmcp_session_sup       (simple_one_for_one → sessions)
└── erlmcp_transport_sup     (one_for_one → transports)
```

Each session is a `gen_statem`; each transport is a `gen_server`.

## Let-It-Crash + Error Boundary

The crash strategy is layered:

- **Inside a request worker:** let it crash. No defensive `try` around
  business logic.
- **At the session-worker boundary:** the session monitors the worker. A
  normal return becomes a JSON-RPC result; an abnormal exit becomes `-32603
  internal error`. The client always gets a spec-compliant response; the
  server stays up.
- **At the public API edge** (`erlmcp:add_tool/2`, client calls): defensive
  validation with `{error, Reason}` returns.

## Validate at the Edge, Crash in the Interior

Input validation happens once, at the session boundary, via `jesse` schema
validation. If the input is invalid, the handler never runs (`-32602`). If
the input passes validation, the handler can assume well-typed data and
crash on anything unexpected — the supervision tree handles the rest.

## Per-Request Worker Processes

Every `tools/call`, `resources/read`, `prompts/get`, and callback dispatch
spawns a monitored worker:

```erlang
{Pid, Ref} = spawn_monitor(fun() ->
    Result = Handler(Args, Ctx),
    Session ! {worker_result, Id, Result}
end)
```

This gives:
- **Fault isolation** — one handler crash cannot corrupt the session
- **Cancellation as exit** — `notifications/cancelled` kills the worker
- **No head-of-line blocking** — concurrent requests run independently

## Cancellation as Process Termination

```erlang
handle_cancelled(Params, Data) ->
    case maps:take(RequestId, Data#data.pending) of
        {{Pid, Ref}, NewPending} ->
            demonitor(Ref, [flush]),
            exit(Pid, cancelled),
            {keep_state, Data#data{pending = NewPending}};
        ...
    end.
```

No `CancellationToken`, no cooperative checks — the BEAM is the primitive.

## Opaque Types at Boundaries

Records are private to modules; exported types use `-opaque`:

```erlang
%% erlmcp_ctx.erl
-opaque ctx() :: #{session := pid(), ...}.
-export_type([ctx/0]).
-spec session(ctx()) -> pid().
```

No shared records across module boundaries.

## Transport Behaviour

```erlang
-callback init(TransportId, Config) -> {ok, state()} | {error, term()}.
-callback send(state(), iodata()) -> ok | {error, term()}.
-callback close(state()) -> ok.
```

All transports deliver inbound data identically
(`Session ! {transport_data, Data}`); the session handles both `cast` and
`info` variants, making it genuinely transport-agnostic.

## Dependency Injection

The `erlmcp_transport_stdio` reader accepts a `read_fun` in its config:

```erlang
erlmcp_transport_stdio:start_link(Id, #{
    session => Session,
    read_fun => fun() -> io:get_line("") end  % default; tests inject controlled funs
})
```

I/O-blocking code is confined to a one-line default; all parsing logic lives
in exported pure functions (`process_raw_input/1`, `prepare_line/1`).
