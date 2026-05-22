-module(erlmcp_server_session).

-behaviour(gen_statem).

-export([start_link/1, send_message/2,
         register_tool/2, unregister_tool/2, list_tools/1,
         register_handler/2, get_instructions/1]).
-export([callback_mode/0, init/1, terminate/3]).
-export([uninitialized/3, initializing/3, operational/3, shutting_down/3]).

-record(data, {
    transport :: pid() | undefined,
    server_info :: erlmcp_model:peer_info(),
    capabilities :: map(),
    protocol_version :: binary() | undefined,
    next_id = 1 :: pos_integer(),
    pending = #{} :: #{pos_integer() => {pid(), reference()}},
    handlers :: map(),
    tools = #{} :: #{binary() => map()},
    instructions :: binary() | undefined
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) when is_map(Opts) ->
    gen_statem:start_link(?MODULE, Opts, []).

-spec send_message(pid(), binary()) -> ok.
send_message(Session, Data) when is_pid(Session), is_binary(Data) ->
    gen_statem:cast(Session, {transport_data, Data}).

-spec register_tool(pid(), map()) -> ok | {error, term()}.
register_tool(Session, ToolSpec) when is_pid(Session), is_map(ToolSpec) ->
    gen_statem:call(Session, {register_tool, ToolSpec}).

-spec unregister_tool(pid(), binary()) -> ok.
unregister_tool(Session, ToolName) when is_pid(Session), is_binary(ToolName) ->
    gen_statem:call(Session, {unregister_tool, ToolName}).

-spec list_tools(pid()) -> [map()].
list_tools(Session) when is_pid(Session) ->
    gen_statem:call(Session, list_tools).

-spec register_handler(pid(), module()) -> ok.
register_handler(Session, Module) when is_pid(Session), is_atom(Module) ->
    gen_statem:call(Session, {register_handler, Module}).

-spec get_instructions(pid()) -> binary() | undefined.
get_instructions(Session) when is_pid(Session) ->
    gen_statem:call(Session, get_instructions).

%%====================================================================
%% gen_statem callbacks
%%====================================================================

callback_mode() ->
    [state_functions].

-spec init(map()) -> gen_statem:init_result(atom()).
init(Opts) ->
    process_flag(trap_exit, true),
    Transport = maps:get(transport, Opts, undefined),
    ServerName = maps:get(name, Opts, <<"erlmcp">>),
    ServerVersion = maps:get(version, Opts, <<"0.6.0">>),
    Caps = maps:get(capabilities, Opts, #{}),
    Handlers = maps:get(handlers, Opts, #{}),
    Data = #data{
        transport = Transport,
        server_info = erlmcp_model:make_server_info(ServerName, ServerVersion),
        capabilities = Caps,
        handlers = Handlers
    },
    {ok, uninitialized, Data}.

%%====================================================================
%% State: uninitialized
%%====================================================================

uninitialized(cast, {transport_data, RawData}, Data) ->
    case erlmcp_json_rpc:decode_and_classify(RawData) of
        {ok, Classified} ->
            handle_uninitialized_message(Classified, Data);
        {error, _Reason} ->
            send_error(Data, null, erlmcp_json_rpc:parse_error(), <<"Parse error">>),
            keep_state_and_data
    end;
uninitialized({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, uninitialized, Data);
uninitialized(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: initializing
%%====================================================================

initializing(cast, {transport_data, _RawData}, _Data) ->
    keep_state_and_data;
initializing({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, initializing, Data);
initializing(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: operational
%%====================================================================

operational(cast, {transport_data, RawData}, Data) ->
    case erlmcp_json_rpc:decode_and_classify(RawData) of
        {ok, Classified} ->
            handle_operational_message(Classified, Data);
        {error, _Reason} ->
            send_error(Data, null, erlmcp_json_rpc:parse_error(), <<"Parse error">>),
            keep_state_and_data
    end;
operational(info, {worker_result, Id, Result}, Data) ->
    handle_worker_result(Id, Result, Data);
operational(info, {'DOWN', Ref, process, Pid, Reason}, Data) ->
    handle_worker_down(Pid, Ref, Reason, Data);
operational(info, {send_notification, _ReqId, Notification}, Data) ->
    send_raw(Data, Notification),
    keep_state_and_data;
operational({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, operational, Data);
operational(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: shutting_down
%%====================================================================

shutting_down({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, shutting_down, Data);
shutting_down(_EventType, _Event, _Data) ->
    keep_state_and_data.

-spec terminate(term(), atom(), #data{}) -> ok.
terminate(_Reason, _State, _Data) ->
    ok.

%%====================================================================
%% Common call handling (all states)
%%====================================================================

handle_common_call(From, get_state, State, _Data) ->
    {keep_state_and_data, [{reply, From, State}]};
handle_common_call(From, {register_tool, ToolSpec}, _State, Data) ->
    do_register_tool(From, ToolSpec, Data);
handle_common_call(From, {unregister_tool, ToolName}, _State, Data) ->
    do_unregister_tool(From, ToolName, Data);
handle_common_call(From, list_tools, _State, Data) ->
    {keep_state_and_data, [{reply, From, maps:values(Data#data.tools)}]};
handle_common_call(From, {register_handler, Module}, _State, Data) ->
    do_register_handler(From, Module, Data);
handle_common_call(From, get_instructions, _State, Data) ->
    {keep_state_and_data, [{reply, From, Data#data.instructions}]};
handle_common_call(From, _Msg, _State, _Data) ->
    {keep_state_and_data, [{reply, From, {error, unknown_request}}]}.

%%====================================================================
%% Message handling — uninitialized
%%====================================================================

handle_uninitialized_message({request, Id, <<"initialize">>, Params}, Data) ->
    handle_initialize(Id, Params, Data);
handle_uninitialized_message({request, Id, _Method, _Params}, Data) ->
    send_error(Data, Id, erlmcp_json_rpc:invalid_request(), <<"Server not initialized">>),
    keep_state_and_data;
handle_uninitialized_message(_, _Data) ->
    keep_state_and_data.

%%====================================================================
%% Message handling — operational
%%====================================================================

handle_operational_message({request, Id, <<"ping">>, _Params}, Data) ->
    handle_ping(Id, Data);
handle_operational_message({request, Id, <<"tools/list">>, Params}, Data) ->
    handle_tools_list(Id, Params, Data);
handle_operational_message({request, Id, <<"tools/call">>, Params}, Data) ->
    handle_tools_call(Id, Params, Data);
handle_operational_message({request, Id, Method, Params}, Data) ->
    handle_request(Id, Method, Params, Data);
handle_operational_message({notification, <<"notifications/cancelled">>, Params}, Data) ->
    handle_cancelled(Params, Data);
handle_operational_message({notification, <<"notifications/initialized">>, _Params}, _Data) ->
    keep_state_and_data;
handle_operational_message(_, _Data) ->
    keep_state_and_data.

%%====================================================================
%% Protocol handlers
%%====================================================================

handle_initialize(Id, Params, Data) ->
    ClientVersion = maps:get(<<"protocolVersion">>, Params, undefined),
    case erlmcp_capabilities:negotiate_version(
             ClientVersion, erlmcp_capabilities:supported_versions()) of
        {ok, Version} ->
            Instructions = generate_instructions(Data),
            ServerCaps = erlmcp_capabilities:build_server_capabilities(
                             derive_capabilities(Data)),
            Result = #{
                <<"protocolVersion">> => Version,
                <<"capabilities">> => ServerCaps,
                <<"serverInfo">> => #{
                    <<"name">> => erlmcp_model:info_name(Data#data.server_info),
                    <<"version">> => erlmcp_model:info_version(Data#data.server_info)
                },
                <<"instructions">> => Instructions
            },
            send_response(Data, Id, Result),
            NewData = Data#data{protocol_version = Version,
                                instructions = Instructions},
            {next_state, operational, NewData};
        {error, no_common_version} ->
            send_error(Data, Id, erlmcp_json_rpc:invalid_params(),
                       <<"Unsupported protocol version">>),
            keep_state_and_data
    end.

handle_ping(Id, Data) ->
    send_response(Data, Id, #{}),
    keep_state_and_data.

handle_request(Id, Method, Params, Data) ->
    Session = self(),
    Transport = Data#data.transport,
    Handlers = Data#data.handlers,
    Ctx = erlmcp_ctx:new(#{
        session => Session,
        transport => Transport,
        request_id => Id
    }),
    {Pid, Ref} = spawn_monitor(fun() ->
        Result = dispatch_request(Method, Params, Handlers, Ctx),
        _ = Session ! {worker_result, Id, Result}
    end),
    NewPending = maps:put(Id, {Pid, Ref}, Data#data.pending),
    {keep_state, Data#data{pending = NewPending}}.

handle_cancelled(Params, Data) ->
    RequestId = maps:get(<<"requestId">>, Params, undefined),
    case maps:take(RequestId, Data#data.pending) of
        {{Pid, Ref}, NewPending} ->
            demonitor(Ref, [flush]),
            exit(Pid, cancelled),
            {keep_state, Data#data{pending = NewPending}};
        error ->
            keep_state_and_data
    end.

%%====================================================================
%% Tools — list & call
%%====================================================================

handle_tools_list(Id, Params, Data) ->
    Sorted = lists:sort(fun(A, B) ->
        maps:get(name, A) =< maps:get(name, B)
    end, maps:values(Data#data.tools)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {PageTools, NextCursor} = paginate(Sorted, Cursor),
    ToolList = [format_tool_for_list(T) || T <- PageTools],
    Result = case NextCursor of
        undefined -> #{<<"tools">> => ToolList};
        _ -> #{<<"tools">> => ToolList, <<"nextCursor">> => NextCursor}
    end,
    send_response(Data, Id, Result),
    keep_state_and_data.

handle_tools_call(Id, Params, Data) ->
    case maps:get(<<"name">>, Params, undefined) of
        undefined ->
            send_error(Data, Id, erlmcp_json_rpc:invalid_params(),
                       <<"Missing tool name">>),
            keep_state_and_data;
        ToolName ->
            Args = maps:get(<<"arguments">>, Params, #{}),
            Meta = maps:get(<<"_meta">>, Params, #{}),
            case maps:get(ToolName, Data#data.tools, undefined) of
                undefined ->
                    send_error(Data, Id, erlmcp_json_rpc:invalid_params(),
                               <<"Unknown tool">>),
                    keep_state_and_data;
                ToolSpec ->
                    case validate_tool_input(ToolSpec, Args) of
                        ok ->
                            dispatch_tool_call(Id, ToolName, Args, ToolSpec, Meta, Data);
                        {error, _} ->
                            send_error(Data, Id, erlmcp_json_rpc:invalid_params(),
                                       <<"Invalid tool arguments">>),
                            keep_state_and_data
                    end
            end
    end.

validate_tool_input(ToolSpec, Args) ->
    case maps:get(input_schema, ToolSpec, undefined) of
        undefined -> ok;
        Schema -> erlmcp_schema:validate(Schema, Args)
    end.

dispatch_tool_call(Id, ToolName, Args, ToolSpec, Meta, Data) ->
    Session = self(),
    Transport = Data#data.transport,
    ProgressToken = maps:get(<<"progressToken">>, Meta, undefined),
    CtxOpts = #{session => Session, transport => Transport, request_id => Id},
    CtxOpts1 = case ProgressToken of
        undefined -> CtxOpts;
        _ -> CtxOpts#{progress_token => ProgressToken}
    end,
    Ctx = erlmcp_ctx:new(CtxOpts1),
    {Pid, Ref} = spawn_monitor(fun() ->
        RawResult = call_tool_handler(ToolName, Args, ToolSpec, Ctx),
        Formatted = format_tool_result(RawResult),
        Result = validate_tool_output(ToolSpec, Formatted),
        _ = Session ! {worker_result, Id, Result}
    end),
    NewPending = maps:put(Id, {Pid, Ref}, Data#data.pending),
    {keep_state, Data#data{pending = NewPending}}.

call_tool_handler(ToolName, Args, ToolSpec, Ctx) ->
    case maps:get(handler, ToolSpec, undefined) of
        Fun when is_function(Fun, 2) ->
            Fun(Args, Ctx);
        {Mod, Fun} when is_atom(Mod), is_atom(Fun) ->
            Mod:Fun(Args, Ctx);
        undefined ->
            HandlerMod = maps:get(handler_module, ToolSpec),
            HandlerMod:handle_tool(ToolName, Args, Ctx)
    end.

format_tool_result({ok, Content}) when is_list(Content) ->
    {ok, #{<<"content">> => Content}};
format_tool_result({ok, SingleItem}) when is_map(SingleItem) ->
    {ok, #{<<"content">> => [SingleItem]}};
format_tool_result({ok, Content, Structured}) when is_list(Content), is_map(Structured) ->
    {ok, #{<<"content">> => Content, <<"structuredContent">> => Structured}};
format_tool_result({ok, SingleItem, Structured}) when is_map(SingleItem), is_map(Structured) ->
    {ok, #{<<"content">> => [SingleItem], <<"structuredContent">> => Structured}};
format_tool_result({error, Code, Msg}) ->
    {error, Code, Msg}.

validate_tool_output(ToolSpec, {ok, ResultMap}) ->
    case maps:get(output_schema, ToolSpec, undefined) of
        undefined ->
            {ok, ResultMap};
        Schema ->
            case maps:get(<<"structuredContent">>, ResultMap, undefined) of
                undefined ->
                    {ok, ResultMap};
                Structured ->
                    case erlmcp_schema:validate(Schema, Structured) of
                        ok -> {ok, ResultMap};
                        {error, _} ->
                            {error, erlmcp_json_rpc:internal_error(),
                             <<"Output schema validation failed">>}
                    end
            end
    end;
validate_tool_output(_, Result) ->
    Result.

%%====================================================================
%% Tools — formatting for tools/list
%%====================================================================

format_tool_for_list(Spec) ->
    Base = #{
        <<"name">> => maps:get(name, Spec),
        <<"description">> => maps:get(description, Spec, <<>>)
    },
    B1 = case maps:get(input_schema, Spec, undefined) of
        undefined -> Base;
        Schema -> Base#{<<"inputSchema">> => Schema}
    end,
    B2 = case maps:get(output_schema, Spec, undefined) of
        undefined -> B1;
        OSchema -> B1#{<<"outputSchema">> => OSchema}
    end,
    B3 = case maps:get(annotations, Spec, undefined) of
        undefined -> B2;
        Ann -> B2#{<<"annotations">> => format_annotations(Ann)}
    end,
    Meta = build_meta(Spec),
    case maps:size(Meta) of
        0 -> B3;
        _ -> B3#{<<"_meta">> => Meta}
    end.

format_annotations(Ann) when is_map(Ann) ->
    maps:fold(fun
        (K, V, Acc) when is_atom(K) ->
            Acc#{atom_to_binary(K, utf8) => V};
        (K, V, Acc) when is_binary(K) ->
            Acc#{K => V}
    end, #{}, Ann).

build_meta(Spec) ->
    Prefix = <<"io.erlmcp/">>,
    Keys = [{category, <<"category">>},
            {when_to_use, <<"when_to_use">>},
            {returns, <<"returns">>},
            {next, <<"next">>},
            {summary, <<"summary">>}],
    lists:foldl(fun({Key, Suffix}, Acc) ->
        case maps:get(Key, Spec, undefined) of
            undefined -> Acc;
            Value -> Acc#{<<Prefix/binary, Suffix/binary>> => Value}
        end
    end, #{}, Keys).

paginate(Tools, undefined) ->
    paginate_from(Tools, 0, 50);
paginate(Tools, Cursor) ->
    Offset = binary_to_integer(base64:decode(Cursor)),
    paginate_from(Tools, Offset, 50).

paginate_from(Tools, Offset, PageSize) ->
    Remaining = lists:nthtail(min(Offset, length(Tools)), Tools),
    case length(Remaining) > PageSize of
        true ->
            Page = lists:sublist(Remaining, PageSize),
            NextCursor = base64:encode(integer_to_binary(Offset + PageSize)),
            {Page, NextCursor};
        false ->
            {Remaining, undefined}
    end.

%%====================================================================
%% Tool registration
%%====================================================================

do_register_tool(From, ToolSpec, Data) ->
    Name = maps:get(name, ToolSpec),
    NewTools = maps:put(Name, ToolSpec, Data#data.tools),
    NewData = Data#data{tools = NewTools},
    maybe_notify_tools_changed(NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

do_unregister_tool(From, ToolName, Data) ->
    NewTools = maps:remove(ToolName, Data#data.tools),
    NewData = Data#data{tools = NewTools},
    maybe_notify_tools_changed(NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

do_register_handler(From, Module, Data) ->
    ToolSpecs = Module:tools(),
    NewTools = lists:foldl(fun(Spec, Acc) ->
        Name = maps:get(name, Spec),
        maps:put(Name, Spec#{handler_module => Module}, Acc)
    end, Data#data.tools, ToolSpecs),
    NewData = Data#data{tools = NewTools},
    maybe_notify_tools_changed(NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

%%====================================================================
%% Capabilities & instructions
%%====================================================================

derive_capabilities(Data) ->
    Base = Data#data.capabilities,
    case maps:size(Data#data.tools) of
        0 -> Base;
        _ -> Base#{<<"tools">> => #{<<"listChanged">> => true}}
    end.

generate_instructions(Data) ->
    Tools = [T || T <- maps:values(Data#data.tools),
                  maps:get(is_directory, T, false) =/= true],
    case Tools of
        [] ->
            <<"This server has no tools registered. Use tools/list to check for updates.">>;
        _ ->
            Categories = lists:usort(
                [maps:get(category, T) || T <- Tools, maps:is_key(category, T)]),
            Explicit = [maps:get(name, T) || T <- Tools,
                            maps:get(entry_point, T, false) =:= true],
            EntryPoints = case Explicit of
                [] ->
                    AllNextTargets = lists:usort(lists:flatten(
                        [maps:get(next, T, []) || T <- Tools])),
                    AllNames = [maps:get(name, T) || T <- Tools],
                    lists:sort([N || N <- AllNames,
                                     not lists:member(N, AllNextTargets)]);
                _ ->
                    lists:sort(Explicit)
            end,
            build_instructions_text(Categories, EntryPoints)
    end.

build_instructions_text(Categories, EntryPoints) ->
    CatPart = case Categories of
        [] -> <<>>;
        _ -> <<" Categories: ", (join_bins(Categories, <<", ">>))/binary, ".">>
    end,
    EPPart = case EntryPoints of
        [] -> <<>>;
        _ -> <<" Start with: ", (join_bins(EntryPoints, <<", ">>))/binary, ".">>
    end,
    <<"This server provides tools organized by category.",
      CatPart/binary, EPPart/binary,
      " Use tools/list for the full catalog.">>.

join_bins([H], _) -> H;
join_bins([H | T], Sep) ->
    lists:foldl(fun(B, Acc) -> <<Acc/binary, Sep/binary, B/binary>> end, H, T).

%%====================================================================
%% Worker completion
%%====================================================================

handle_worker_result(Id, {ok, Result}, Data) ->
    case maps:take(Id, Data#data.pending) of
        {{_Pid, Ref}, NewPending} ->
            demonitor(Ref, [flush]),
            send_response(Data, Id, Result),
            {keep_state, Data#data{pending = NewPending}};
        error ->
            keep_state_and_data
    end;
handle_worker_result(Id, {error, Code, Message}, Data) ->
    case maps:take(Id, Data#data.pending) of
        {{_Pid, Ref}, NewPending} ->
            demonitor(Ref, [flush]),
            send_error(Data, Id, Code, Message),
            {keep_state, Data#data{pending = NewPending}};
        error ->
            keep_state_and_data
    end;
handle_worker_result(_, _, _) ->
    keep_state_and_data.

handle_worker_down(Pid, Ref, Reason, Data) ->
    case find_request_by_worker(Pid, Data#data.pending) of
        {ok, Id} ->
            demonitor(Ref, [flush]),
            NewPending = maps:remove(Id, Data#data.pending),
            case Reason of
                normal ->
                    {keep_state, Data#data{pending = NewPending}};
                cancelled ->
                    {keep_state, Data#data{pending = NewPending}};
                _ ->
                    send_error(Data, Id, erlmcp_json_rpc:internal_error(),
                               <<"Internal error">>),
                    {keep_state, Data#data{pending = NewPending}}
            end;
        error ->
            keep_state_and_data
    end.

%%====================================================================
%% Request dispatch (M1 generic handler path)
%%====================================================================

dispatch_request(Method, Params, Handlers, Ctx) ->
    case maps:get(Method, Handlers, undefined) of
        undefined ->
            {error, erlmcp_json_rpc:method_not_found(), <<"Method not found">>};
        Handler when is_function(Handler, 2) ->
            Handler(Params, Ctx);
        {Mod, Fun} ->
            Mod:Fun(Params, Ctx)
    end.

%%====================================================================
%% Wire helpers
%%====================================================================

send_response(#data{transport = Transport}, Id, Result) when is_pid(Transport) ->
    Json = erlmcp_json_rpc:encode_response(Id, Result),
    Transport ! {send, Json},
    ok;
send_response(_, _, _) ->
    ok.

send_error(#data{transport = Transport}, Id, Code, Message) when is_pid(Transport) ->
    Json = erlmcp_json_rpc:encode_error_response(Id, Code, Message),
    Transport ! {send, Json},
    ok;
send_error(_, _, _, _) ->
    ok.

send_raw(#data{transport = Transport}, Json) when is_pid(Transport) ->
    Transport ! {send, Json},
    ok;
send_raw(_, _) ->
    ok.

maybe_notify_tools_changed(#data{protocol_version = undefined}) ->
    ok;
maybe_notify_tools_changed(Data) ->
    Json = erlmcp_json_rpc:encode_notification(
               <<"notifications/tools/list_changed">>, #{}),
    send_raw(Data, Json).

%%====================================================================
%% Internal helpers
%%====================================================================

find_request_by_worker(Pid, Pending) ->
    maps:fold(
        fun(Id, {P, _Ref}, error) when P =:= Pid -> {ok, Id};
           (_Id, _Val, Acc) -> Acc
        end,
        error,
        Pending
    ).
