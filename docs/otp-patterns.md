# OTP Patterns in erlmcp

## Supervision Trees

### Application Structure
```
erlmcp_app
└── erlmcp_sup (one_for_one)
    ├── erlmcp_client_sup (simple_one_for_one)
    │   └── erlmcp_client workers
    └── erlmcp_server_sup (simple_one_for_one)
        └── erlmcp_server workers
```

### Restart Strategies

**Main Supervisor** - `one_for_one`
- Isolated failures
- Independent services

**Client/Server Supervisors** - `simple_one_for_one`
- Dynamic children
- Uniform worker type

## gen_server Pattern

### Client Implementation
```erlang
%% Synchronous call with timeout
handle_call({calculate, Expression}, From, State) ->
    %% Send async request
    RequestId = send_request(Expression, State),
    %% Store pending request
    NewState = store_pending(RequestId, From, State),
    %% Don't reply yet
    {noreply, NewState}.

%% Handle async response
handle_info({response, RequestId, Result}, State) ->
    case take_pending(RequestId, State) of
        {ok, From, NewState} ->
            gen_server:reply(From, Result),
            {noreply, NewState};
        error ->
            {noreply, State}
    end.
```

### Server Implementation
```erlang
%% Resource management
handle_call({add_resource, Uri, Handler}, _From, State) ->
    NewState = State#state{
        resources = maps:put(Uri, Handler, State#state.resources)
    },
    {reply, ok, NewState}.

%% Async notifications
handle_cast({notify_subscribers, Event}, State) ->
    spawn(fun() -> 
        notify_all(State#state.subscribers, Event) 
    end),
    {noreply, State}.
```

## gen_statem Pattern

### Connection State Machine
```erlang
%% State definitions
-type state() :: disconnected | connecting | connected | ready.

%% State callback
disconnected({call, From}, connect, Data) ->
    {next_state, connecting, Data, 
     [{reply, From, ok}, {state_timeout, 5000, connect}]}.

connecting(state_timeout, connect, Data) ->
    case try_connect(Data) of
        {ok, Socket} ->
            {next_state, connected, Data#data{socket = Socket}};
        {error, _} ->
            {next_state, disconnected, Data,
             [{state_timeout, backoff(Data), retry}]}
    end.
```

## Process Design Patterns

### 1. Request-Response Correlation
```erlang
-record(state, {
    request_id = 1 :: integer(),
    pending = #{} :: #{integer() => {pid(), reference()}}
}).

send_request(Method, Params, #state{request_id = Id} = State) ->
    %% Send with correlation ID
    send_message(#{id => Id, method => Method, params => Params}),
    %% Track pending request
    Ref = make_ref(),
    NewPending = maps:put(Id, {self(), Ref}, State#state.pending),
    State#state{request_id = Id + 1, pending = NewPending}.
```

### 2. Subscription Management
```erlang
%% Using sets for efficient lookups
-record(state, {
    subscriptions = #{} :: #{binary() => sets:set(pid())}
}).

subscribe(Uri, Pid, State) ->
    Subs = maps:get(Uri, State#state.subscriptions, sets:new()),
    NewSubs = sets:add_element(Pid, Subs),
    State#state{
        subscriptions = maps:put(Uri, NewSubs, State#state.subscriptions)
    }.
```

### 3. Process Monitoring
```erlang
init(Args) ->
    process_flag(trap_exit, true),
    {ok, initialize_state(Args)}.

handle_info({'EXIT', Pid, Reason}, State) ->
    %% Clean up after crashed process
    NewState = cleanup_process(Pid, State),
    {noreply, NewState}.
```

## Error Handling Patterns

### 1. Let It Crash
```erlang
%% Don't defend against impossible cases
handle_call({get_resource, Uri}, _From, State) ->
    %% Let it crash if resource doesn't exist
    #{Uri := Handler} = State#state.resources,
    Result = Handler(Uri),
    {reply, Result, State}.
```

### 2. Graceful Degradation
```erlang
%% Client continues working despite errors
handle_info({tcp_closed, Socket}, State) ->
    %% Log and reconnect
    logger:warning("Connection lost, attempting reconnect"),
    {next_state, connecting, State#state{socket = undefined}}.
```

### 3. Circuit Breaker
```erlang
-record(breaker, {
    state = closed :: closed | open | half_open,
    failures = 0 :: integer(),
    threshold = 5 :: integer(),
    timeout :: reference()
}).

call_with_breaker(Fun, Breaker) ->
    case Breaker#breaker.state of
        open ->
            {error, circuit_open};
        _ ->
            try Fun() of
                Result ->
                    {Result, reset_breaker(Breaker)}
            catch
                _:_ ->
                    {error, trip_breaker(Breaker)}
            end
    end.
```

## Performance Patterns

### 1. Selective Receive
```erlang
%% Prioritize important messages
handle_info(Info, State) ->
    receive
        {priority, Msg} ->
            handle_priority(Msg, State)
    after 0 ->
        handle_normal(Info, State)
    end.
```

### 2. Batch Processing
```erlang
%% Accumulate requests
handle_cast({request, Req}, #state{batch = Batch} = State) ->
    NewBatch = [Req | Batch],
    case length(NewBatch) >= 100 of
        true ->
            process_batch(NewBatch),
            {noreply, State#state{batch = []}};
        false ->
            {noreply, State#state{batch = NewBatch}}
    end.
```

### 3. ETS for Shared State
```erlang
%% Read-heavy workload optimization
init(Name) ->
    Tab = ets:new(Name, [named_table, public, {read_concurrency, true}]),
    {ok, #state{table = Tab}}.

%% Readers access ETS directly
lookup(Name, Key) ->
    case ets:lookup(Name, Key) of
        [{_, Value}] -> {ok, Value};
        [] -> {error, not_found}
    end.
```

## Testing Patterns

### 1. Mocking with Processes
```erlang
%% Test helper
mock_server(Responses) ->
    spawn(fun() -> mock_loop(Responses) end).

mock_loop([{Request, Response} | Rest]) ->
    receive
        Request -> 
            sender() ! Response,
            mock_loop(Rest)
    end.
```

### 2. Property-Based Testing
```erlang
prop_resource_handler() ->
    ?FORALL(Uri, binary(),
        begin
            {ok, Server} = start_server(),
            Handler = fun(_) -> <<"test">> end,
            ok = erlmcp_server:add_resource(Server, Uri, Handler),
            {ok, <<"test">>} =:= get_resource(Server, Uri)
        end).
```

## Common Pitfalls

1. **Don't block in init/1** - Do async initialization
2. **Avoid large messages** - Use references to shared data
3. **Monitor critical processes** - Clean up when they die
4. **Set proper timeouts** - Prevent hanging calls
5. **Use supervisors** - Don't spawn unsupervised processes