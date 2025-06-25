-module(erlmcp_client).
-behaviour(gen_server).

-include("erlmcp.hrl").

%% API exports
-export([
    start_link/1, start_link/2,
    initialize/2, initialize/3,
    list_roots/1,
    list_resources/1, list_resource_templates/1,
    read_resource/2, subscribe_to_resource/2, unsubscribe_from_resource/2,
    list_prompts/1, get_prompt/2, get_prompt/3,
    list_tools/1, call_tool/3,
    with_batch/2, send_batch_request/4,
    set_notification_handler/3, remove_notification_handler/2,
    set_sampling_handler/2, remove_sampling_handler/1,
    set_strict_mode/2,
    stop/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Types
-type client() :: pid().
-type transport_opts() :: {stdio, list()} | {tcp, map()} | {http, map()}.
-type client_opts() :: #{
    strict_mode => boolean(),
    timeout => timeout(),
    _ => _
}.
-type request_id() :: pos_integer().
-type batch_id() :: reference().
-type notification_handler() :: fun((binary(), map()) -> any()) | {module(), atom()}.
-type sampling_handler() :: fun((binary(), map()) -> any()) | {module(), atom()} | pid().

-export_type([client/0, transport_opts/0, client_opts/0]).

%% State record with better type specifications
-record(state, {
    transport :: module(),
    transport_state :: term(),
    capabilities :: #mcp_server_capabilities{} | undefined,
    request_id = 1 :: request_id(),
    pending_requests = #{} :: #{request_id() => {atom(), pid()}},
    batch_requests = #{} :: #{batch_id() => [{request_id(), binary(), map()}]},
    notification_handlers = #{} :: #{binary() => notification_handler()},
    sampling_handler :: sampling_handler() | undefined,
    strict_mode = false :: boolean(),
    subscriptions = sets:set() :: sets:set(binary()),
    initialized = false :: boolean(),
    timeout = 5000 :: timeout()
}).

-type state() :: #state{}.

%% Macros for common patterns
-define(CALL_TIMEOUT(State), State#state.timeout).
-define(IS_INITIALIZED(State), State#state.initialized).
-define(CHECK_CAPABILITY(State, Cap), 
    case validate_capability(State, Cap) of
        ok -> do_request;
        {error, _} = Error -> Error
    end).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link(transport_opts()) -> {ok, client()} | {error, term()}.
start_link(TransportOpts) ->
    start_link(TransportOpts, #{}).

-spec start_link(transport_opts(), client_opts()) -> {ok, client()} | {error, term()}.
start_link(TransportOpts, Options) ->
    gen_server:start_link(?MODULE, [TransportOpts, Options], []).

-spec initialize(client(), #mcp_client_capabilities{}) -> 
    {ok, map()} | {error, term()}.
initialize(Client, Capabilities) ->
    initialize(Client, Capabilities, #{}).

-spec initialize(client(), #mcp_client_capabilities{}, map()) -> 
    {ok, map()} | {error, term()}.
initialize(Client, Capabilities, Options) ->
    gen_server:call(Client, {initialize, Capabilities, Options}, infinity).

-spec list_roots(client()) -> {ok, [map()]} | {error, term()}.
list_roots(Client) ->
    gen_server:call(Client, list_roots).

-spec list_resources(client()) -> {ok, [map()]} | {error, term()}.
list_resources(Client) ->
    gen_server:call(Client, list_resources).

-spec read_resource(client(), binary()) -> {ok, map()} | {error, term()}.
read_resource(Client, Uri) when is_binary(Uri) ->
    gen_server:call(Client, {read_resource, Uri}).

-spec list_prompts(client()) -> {ok, [map()]} | {error, term()}.
list_prompts(Client) ->
    gen_server:call(Client, list_prompts).

-spec get_prompt(client(), binary()) -> {ok, map()} | {error, term()}.
get_prompt(Client, Name) when is_binary(Name) ->
    get_prompt(Client, Name, #{}).

-spec get_prompt(client(), binary(), map()) -> {ok, map()} | {error, term()}.
get_prompt(Client, Name, Arguments) when is_binary(Name), is_map(Arguments) ->
    gen_server:call(Client, {get_prompt, Name, Arguments}).

-spec list_tools(client()) -> {ok, [map()]} | {error, term()}.
list_tools(Client) ->
    gen_server:call(Client, list_tools).

-spec call_tool(client(), binary(), map()) -> {ok, map()} | {error, term()}.
call_tool(Client, Name, Arguments) when is_binary(Name), is_map(Arguments) ->
    gen_server:call(Client, {call_tool, Name, Arguments}).

-spec stop(client()) -> ok.
stop(Client) ->
    gen_server:stop(Client).

-spec list_resource_templates(client()) -> {ok, [map()]} | {error, term()}.
list_resource_templates(Client) ->
    gen_server:call(Client, list_resource_templates).

-spec subscribe_to_resource(client(), binary()) -> ok | {error, term()}.
subscribe_to_resource(Client, Uri) when is_binary(Uri) ->
    gen_server:call(Client, {subscribe_resource, Uri}).

-spec unsubscribe_from_resource(client(), binary()) -> ok | {error, term()}.
unsubscribe_from_resource(Client, Uri) when is_binary(Uri) ->
    gen_server:call(Client, {unsubscribe_resource, Uri}).

-spec with_batch(client(), fun((batch_id()) -> Result)) -> Result when Result :: term().
with_batch(Client, BatchFun) when is_function(BatchFun, 1) ->
    BatchId = make_ref(),
    ok = gen_server:call(Client, {start_batch, BatchId}),
    try
        Result = BatchFun(BatchId),
        {ok, _Count} = gen_server:call(Client, {execute_batch, BatchId}),
        Result
    catch
        Class:Reason:Stacktrace ->
            gen_server:call(Client, {cancel_batch, BatchId}),
            erlang:raise(Class, Reason, Stacktrace)
    end.

-spec send_batch_request(client(), batch_id(), binary(), map()) -> 
    {ok, request_id()} | {error, term()}.
send_batch_request(Client, BatchId, Method, Params) 
  when is_reference(BatchId), is_binary(Method), is_map(Params) ->
    gen_server:call(Client, {add_to_batch, BatchId, Method, Params}).

-spec set_notification_handler(client(), binary(), notification_handler()) -> ok.
set_notification_handler(Client, Method, Handler) when is_binary(Method) ->
    gen_server:call(Client, {set_notification_handler, Method, Handler}).

-spec remove_notification_handler(client(), binary()) -> ok.
remove_notification_handler(Client, Method) when is_binary(Method) ->
    gen_server:call(Client, {remove_notification_handler, Method}).

-spec set_sampling_handler(client(), sampling_handler()) -> ok.
set_sampling_handler(Client, Handler) ->
    gen_server:call(Client, {set_sampling_handler, Handler}).

-spec remove_sampling_handler(client()) -> ok.
remove_sampling_handler(Client) ->
    gen_server:call(Client, remove_sampling_handler).

-spec set_strict_mode(client(), boolean()) -> ok.
set_strict_mode(Client, Enabled) when is_boolean(Enabled) ->
    gen_server:call(Client, {set_strict_mode, Enabled}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init([transport_opts() | client_opts()]) -> {ok, state()}.
init([TransportOpts, Options]) ->
    process_flag(trap_exit, true),
    case init_transport(TransportOpts) of
        {ok, Transport, TransportState} ->
            State = #state{
                transport = Transport,
                transport_state = TransportState,
                strict_mode = maps:get(strict_mode, Options, false),
                timeout = maps:get(timeout, Options, 5000),
                subscriptions = sets:new()
            },
            {ok, State};
        {error, Reason} ->
            {stop, Reason}
    end.

-spec handle_call(term(), {pid(), term()}, state()) -> 
    {reply, term(), state()} | 
    {noreply, state()} |
    {stop, term(), term(), state()}.

handle_call({initialize, Capabilities, _Options}, From, State) ->
    Request = build_initialize_request(Capabilities),
    send_request(State, <<"initialize">>, Request, {initialize, From});

handle_call(list_resources, From, State) ->
    case ?CHECK_CAPABILITY(State, resources) of
        do_request ->
            send_request(State, <<"resources/list">>, #{}, {list_resources, From});
        Error ->
            {reply, Error, State}
    end;

handle_call({read_resource, Uri}, From, State) ->
    case ?CHECK_CAPABILITY(State, resources) of
        do_request ->
            Params = #{<<"uri">> => Uri},
            send_request(State, <<"resources/read">>, Params, {read_resource, From});
        Error ->
            {reply, Error, State}
    end;

handle_call(list_tools, From, State) ->
    case ?CHECK_CAPABILITY(State, tools) of
        do_request ->
            send_request(State, <<"tools/list">>, #{}, {list_tools, From});
        Error ->
            {reply, Error, State}
    end;

handle_call({call_tool, Name, Arguments}, From, State) ->
    case ?CHECK_CAPABILITY(State, tools) of
        do_request ->
            Params = #{<<"name">> => Name, <<"arguments">> => Arguments},
            send_request(State, <<"tools/call">>, Params, {call_tool, From});
        Error ->
            {reply, Error, State}
    end;

handle_call(list_prompts, From, State) ->
    case ?CHECK_CAPABILITY(State, prompts) of
        do_request ->
            send_request(State, <<"prompts/list">>, #{}, {list_prompts, From});
        Error ->
            {reply, Error, State}
    end;

handle_call({get_prompt, Name, Arguments}, From, State) ->
    case ?CHECK_CAPABILITY(State, prompts) of
        do_request ->
            Params = build_prompt_params(Name, Arguments),
            send_request(State, <<"prompts/get">>, Params, {get_prompt, From});
        Error ->
            {reply, Error, State}
    end;

handle_call(list_resource_templates, From, State) ->
    case ?CHECK_CAPABILITY(State, resources) of
        do_request ->
            send_request(State, <<"resources/templates/list">>, #{}, {list_resource_templates, From});
        Error ->
            {reply, Error, State}
    end;

handle_call({subscribe_resource, Uri}, From, State) ->
    case ?CHECK_CAPABILITY(State, resources) of
        do_request ->
            Params = #{<<"uri">> => Uri},
            NewState = State#state{
                subscriptions = sets:add_element(Uri, State#state.subscriptions)
            },
            send_request(NewState, <<"resources/subscribe">>, Params, {subscribe_resource, From});
        Error ->
            {reply, Error, State}
    end;

handle_call({unsubscribe_resource, Uri}, From, State) ->
    case ?CHECK_CAPABILITY(State, resources) of
        do_request ->
            Params = #{<<"uri">> => Uri},
            NewState = State#state{
                subscriptions = sets:del_element(Uri, State#state.subscriptions)
            },
            send_request(NewState, <<"resources/unsubscribe">>, Params, {unsubscribe_resource, From});
        Error ->
            {reply, Error, State}
    end;

handle_call({start_batch, BatchId}, _From, State) ->
    NewBatches = maps:put(BatchId, [], State#state.batch_requests),
    {reply, ok, State#state{batch_requests = NewBatches}};

handle_call({add_to_batch, BatchId, Method, Params}, _From, State) ->
    case maps:find(BatchId, State#state.batch_requests) of
        {ok, Requests} ->
            RequestId = State#state.request_id,
            Request = {RequestId, Method, Params},
            NewRequests = [Request | Requests],
            NewState = State#state{
                request_id = RequestId + 1,
                batch_requests = maps:put(BatchId, NewRequests, State#state.batch_requests)
            },
            {reply, {ok, RequestId}, NewState};
        error ->
            {reply, {error, batch_not_found}, State}
    end;

handle_call({execute_batch, BatchId}, _From, State) ->
    case maps:take(BatchId, State#state.batch_requests) of
        {Requests, NewBatches} ->
            NewState = State#state{batch_requests = NewBatches},
            execute_batch_requests(lists:reverse(Requests), NewState),
            {reply, {ok, length(Requests)}, NewState};
        error ->
            {reply, {error, batch_not_found}, State}
    end;

handle_call({cancel_batch, BatchId}, _From, State) ->
    NewBatches = maps:remove(BatchId, State#state.batch_requests),
    {reply, ok, State#state{batch_requests = NewBatches}};

handle_call({set_notification_handler, Method, Handler}, _From, State) ->
    NewHandlers = maps:put(Method, Handler, State#state.notification_handlers),
    {reply, ok, State#state{notification_handlers = NewHandlers}};

handle_call({remove_notification_handler, Method}, _From, State) ->
    NewHandlers = maps:remove(Method, State#state.notification_handlers),
    {reply, ok, State#state{notification_handlers = NewHandlers}};

handle_call({set_sampling_handler, Handler}, _From, State) ->
    {reply, ok, State#state{sampling_handler = Handler}};

handle_call(remove_sampling_handler, _From, State) ->
    {reply, ok, State#state{sampling_handler = undefined}};

handle_call({set_strict_mode, Enabled}, _From, State) ->
    {reply, ok, State#state{strict_mode = Enabled}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info({transport_message, Data}, State) ->
    case erlmcp_json_rpc:decode_message(Data) of
        {ok, #json_rpc_response{id = Id, result = Result, error = undefined}} ->
            handle_response(Id, {ok, Result}, State);
        {ok, #json_rpc_response{id = Id, error = Error}} ->
            handle_response(Id, {error, Error}, State);
        {ok, #json_rpc_notification{method = Method, params = Params}} ->
            handle_notification(Method, Params, State);
        {error, Reason} ->
            logger:error("Failed to decode message: ~p", [Reason]),
            {noreply, State}
    end;

handle_info({'EXIT', Pid, Reason}, State) when Pid =:= State#state.transport_state ->
    logger:error("Transport process died: ~p", [Reason]),
    {stop, {transport_died, Reason}, State};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    close_transport(State),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

-spec init_transport(transport_opts()) -> 
    {ok, module(), term()} | {error, term()}.
init_transport({stdio, _Opts}) ->
    {ok, erlmcp_transport_stdio, self()};
init_transport({tcp, Opts}) ->
    {ok, erlmcp_transport_tcp, Opts};
init_transport({http, Opts}) ->
    case erlmcp_transport_http:init(Opts) of
        {ok, State} -> {ok, erlmcp_transport_http, State};
        {error, _} = Error -> Error
    end.

-spec close_transport(state()) -> ok.
close_transport(#state{transport = Transport, transport_state = TransportState}) ->
    catch Transport:close(TransportState),
    ok.

-spec send_request(state(), binary(), map(), {atom(), pid()}) -> 
    {noreply, state()} | {reply, {error, term()}, state()}.
send_request(State, Method, Params, RequestInfo) ->
    RequestId = State#state.request_id,
    Json = erlmcp_json_rpc:encode_request(RequestId, Method, Params),
    case send_message(State, Json) of
        ok ->
            NewState = State#state{
                request_id = RequestId + 1,
                pending_requests = maps:put(RequestId, RequestInfo, State#state.pending_requests)
            },
            {noreply, NewState};
        {error, Reason} ->
            {_, From} = RequestInfo,
            {reply, {error, Reason}, State}
    end.

-spec send_message(state(), binary()) -> ok | {error, term()}.
send_message(#state{transport = Transport, transport_state = TransportState}, Message) ->
    Transport:send(TransportState, Message).

-spec build_initialize_request(#mcp_client_capabilities{}) -> map().
build_initialize_request(Capabilities) ->
    #{
        <<"protocolVersion">> => ?MCP_VERSION,
        <<"capabilities">> => encode_capabilities(Capabilities),
        <<"clientInfo">> => #{
            <<"name">> => <<"erlmcp">>,
            <<"version">> => <<"0.1.0">>
        }
    }.

-spec build_prompt_params(binary(), map()) -> map().
build_prompt_params(Name, Arguments) when map_size(Arguments) =:= 0 ->
    #{<<"name">> => Name};
build_prompt_params(Name, Arguments) ->
    #{<<"name">> => Name, <<"arguments">> => Arguments}.

-spec encode_capabilities(#mcp_client_capabilities{}) -> map().
encode_capabilities(#mcp_client_capabilities{} = Caps) ->
    Base = #{},
    Base1 = maybe_add_capability(Base, <<"roots">>, Caps#mcp_client_capabilities.roots),
    Base2 = maybe_add_capability(Base1, <<"sampling">>, Caps#mcp_client_capabilities.sampling),
    maybe_merge_experimental(Base2, Caps#mcp_client_capabilities.experimental).

-spec maybe_add_capability(map(), binary(), #mcp_capability{} | undefined) -> map().
maybe_add_capability(Map, _Key, undefined) ->
    Map;
maybe_add_capability(Map, Key, #mcp_capability{enabled = true}) ->
    Map#{Key => #{}};
maybe_add_capability(Map, _Key, _) ->
    Map.

-spec maybe_merge_experimental(map(), map() | undefined) -> map().
maybe_merge_experimental(Map, undefined) ->
    Map;
maybe_merge_experimental(Map, Experimental) when is_map(Experimental) ->
    maps:merge(Map, Experimental);
maybe_merge_experimental(Map, _) ->
    Map.

-spec validate_capability(state(), atom()) -> ok | {error, term()}.
validate_capability(#state{strict_mode = false}, _) ->
    ok;
validate_capability(#state{initialized = false}, _) ->
    {error, not_initialized};
validate_capability(#state{capabilities = undefined}, _) ->
    {error, no_server_capabilities};
validate_capability(#state{capabilities = Caps}, Capability) ->
    check_server_capability(Caps, Capability).

-spec check_server_capability(#mcp_server_capabilities{}, atom()) -> 
    ok | {error, capability_not_supported}.
check_server_capability(Caps, resources) ->
    check_capability_enabled(Caps#mcp_server_capabilities.resources);
check_server_capability(Caps, tools) ->
    check_capability_enabled(Caps#mcp_server_capabilities.tools);
check_server_capability(Caps, prompts) ->
    check_capability_enabled(Caps#mcp_server_capabilities.prompts);
check_server_capability(_Caps, _) ->
    ok.

-spec check_capability_enabled(#mcp_capability{} | undefined) -> 
    ok | {error, capability_not_supported}.
check_capability_enabled(#mcp_capability{enabled = true}) ->
    ok;
check_capability_enabled(_) ->
    {error, capability_not_supported}.

-spec handle_response(request_id(), {ok, map()} | {error, map()}, state()) -> 
    {noreply, state()}.
handle_response(Id, Result, State) ->
    case maps:take(Id, State#state.pending_requests) of
        {{initialize, From}, NewPending} ->
            gen_server:reply(From, Result),
            case Result of
                {ok, InitResult} ->
                    ServerCapabilities = extract_server_capabilities(InitResult),
                    NewState = State#state{
                        pending_requests = NewPending,
                        capabilities = ServerCapabilities,
                        initialized = true
                    },
                    {noreply, NewState};
                {error, _} ->
                    {noreply, State#state{pending_requests = NewPending}}
            end;
        {{_RequestType, From}, NewPending} ->
            gen_server:reply(From, Result),
            {noreply, State#state{pending_requests = NewPending}};
        error ->
            logger:warning("Received response for unknown request ID: ~p", [Id]),
            {noreply, State}
    end.

-spec extract_server_capabilities(map()) -> #mcp_server_capabilities{} | undefined.
extract_server_capabilities(InitResult) ->
    case maps:get(<<"capabilities">>, InitResult, undefined) of
        undefined ->
            undefined;
        Caps when is_map(Caps) ->
            #mcp_server_capabilities{
                resources = extract_capability(maps:get(<<"resources">>, Caps, undefined)),
                tools = extract_capability(maps:get(<<"tools">>, Caps, undefined)),
                prompts = extract_capability(maps:get(<<"prompts">>, Caps, undefined)),
                logging = extract_capability(maps:get(<<"logging">>, Caps, undefined))
            }
    end.

-spec extract_capability(map() | undefined) -> #mcp_capability{} | undefined.
extract_capability(undefined) ->
    undefined;
extract_capability(Cap) when is_map(Cap) ->
    #mcp_capability{enabled = true};
extract_capability(_) ->
    undefined.

-spec handle_notification(binary(), map(), state()) -> {noreply, state()}.
handle_notification(<<"sampling/createMessage">> = Method, Params, State) ->
    spawn_handler(State#state.sampling_handler, Method, Params),
    {noreply, State};

handle_notification(<<"resources/updated">> = Method, Params, State) ->
    case maps:get(<<"uri">>, Params, undefined) of
        undefined ->
            {noreply, State};
        Uri ->
            case sets:is_element(Uri, State#state.subscriptions) of
                true ->
                    invoke_notification_handler(Method, Params, State);
                false ->
                    {noreply, State}
            end
    end;

handle_notification(<<"resources/list_changed">> = Method, Params, State) ->
    invoke_notification_handler(Method, Params, State);

handle_notification(Method, Params, State) ->
    invoke_notification_handler(Method, Params, State).

-spec invoke_notification_handler(binary(), map(), state()) -> {noreply, state()}.
invoke_notification_handler(Method, Params, State) ->
    case maps:get(Method, State#state.notification_handlers, undefined) of
        undefined ->
            logger:info("Unhandled notification: ~p", [Method]),
            {noreply, State};
        Handler ->
            spawn_handler(Handler, Method, Params),
            {noreply, State}
    end.

-spec spawn_handler(notification_handler() | undefined, binary(), map()) -> ok.
spawn_handler(undefined, Method, _Params) ->
    logger:warning("No handler for: ~p", [Method]),
    ok;
spawn_handler(Handler, Method, Params) when is_function(Handler, 2) ->
    spawn(fun() -> 
        try Handler(Method, Params)
        catch Class:Reason:Stack ->
            logger:error("Handler crashed: ~p:~p~n~p", [Class, Reason, Stack])
        end
    end),
    ok;
spawn_handler({Module, Function}, Method, Params) ->
    spawn(fun() -> 
        try Module:Function(Method, Params)
        catch Class:Reason:Stack ->
            logger:error("Handler crashed: ~p:~p~n~p", [Class, Reason, Stack])
        end
    end),
    ok;
spawn_handler(Pid, Method, Params) when is_pid(Pid) ->
    Pid ! {sampling_request, Method, Params},
    ok.

-spec execute_batch_requests([{request_id(), binary(), map()}], state()) -> ok.
execute_batch_requests([], _State) ->
    ok;
execute_batch_requests([{RequestId, Method, Params} | Rest], State) ->
    Json = erlmcp_json_rpc:encode_request(RequestId, Method, Params),
    send_message(State, Json),
    execute_batch_requests(Rest, State).