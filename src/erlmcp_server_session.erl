-module(erlmcp_server_session).

-behaviour(gen_statem).

-include_lib("kernel/include/logger.hrl").

%% API
-export([start_link/1, send_message/2, send_message/3, get_instructions/1]).
%% Logging (M2b)
-export([set_log_level/2, emit_log/4]).
%% gen_statem
-export([callback_mode/0, init/1, terminate/3]).
-export([uninitialized/3, operational/3, shutting_down/3]).

-record(data, {
    server_ref :: ets:tid(),
    server_pid :: erlmcp_server:server() | undefined,
    responder :: erlmcp_reply:responder() | undefined,
    server_info :: erlmcp_model:peer_info(),
    capabilities :: map(),
    protocol_version :: binary() | undefined,
    next_id = 1 :: pos_integer(),
    pending = #{} :: #{pos_integer() => {pid(), reference(), erlmcp_reply:responder()}},
    tasks = #{} :: #{binary() => pid()},
    out_pending = #{} :: #{pos_integer() => {pid(), reference()}},
    out_next_id = 1 :: pos_integer(),
    subscriptions = #{} :: #{binary() => true},
    log_level = emergency :: atom(),
    instructions :: binary() | undefined
}).

-define(LOG_LEVELS, [debug, info, notice, warning, error, critical, alert, emergency]).

%%====================================================================
%% API
%%====================================================================

-spec start_link(map()) -> gen_statem:start_ret().
start_link(Opts) when is_map(Opts) ->
    gen_statem:start_link(?MODULE, Opts, []).

-spec send_message(pid(), binary()) -> ok.
send_message(Session, Data) when is_pid(Session), is_binary(Data) ->
    gen_statem:cast(Session, {transport_data, Data}).

-spec send_message(pid(), binary(), erlmcp_reply:responder()) -> ok.
send_message(Session, Data, Responder) when is_pid(Session), is_binary(Data) ->
    gen_statem:cast(Session, {transport_data, Data, Responder}).

-spec get_instructions(pid()) -> binary() | undefined.
get_instructions(Session) when is_pid(Session) ->
    gen_statem:call(Session, get_instructions).

-spec set_log_level(pid(), atom()) -> ok.
set_log_level(Session, Level) when is_pid(Session), is_atom(Level) ->
    gen_statem:call(Session, {set_log_level, Level}).

-spec emit_log(pid(), atom(), binary(), term()) -> ok.
emit_log(Session, Level, Logger, LogData) when is_pid(Session), is_atom(Level) ->
    gen_statem:cast(Session, {emit_log, Level, Logger, LogData}).

%%====================================================================
%% gen_statem callbacks
%%====================================================================

callback_mode() ->
    [state_functions].

-spec init(map()) -> gen_statem:init_result(atom()).
init(Opts) ->
    process_flag(trap_exit, true),
    ServerPid = maps:get(server, Opts, undefined),
    Tab = case ServerPid of
        undefined -> undefined;
        Pid -> erlmcp_server:catalog_table(Pid)
    end,
    case ServerPid of
        undefined -> ok;
        _ -> erlmcp_server:register_session(ServerPid, self())
    end,
    Responder = maps:get(responder, Opts, undefined),
    ServerName = maps:get(name, Opts, <<"erlmcp">>),
    ServerVersion = maps:get(version, Opts, <<"0.6.0">>),
    Caps = maps:get(capabilities, Opts, #{}),
    Data = #data{
        server_ref = Tab,
        server_pid = ServerPid,
        responder = Responder,
        server_info = erlmcp_model:make_server_info(ServerName, ServerVersion),
        capabilities = Caps
    },
    {ok, uninitialized, Data}.

%%====================================================================
%% State: uninitialized
%%====================================================================

uninitialized(cast, {transport_data, RawData}, Data) ->
    handle_uninitialized_data(RawData, Data, Data#data.responder);
uninitialized(cast, {transport_data, RawData, Responder}, Data) ->
    handle_uninitialized_data(RawData, Data, Responder);
uninitialized(info, {transport_data, RawData}, Data) ->
    handle_uninitialized_data(RawData, Data, Data#data.responder);
uninitialized(info, {transport_data, RawData, Responder}, Data) ->
    handle_uninitialized_data(RawData, Data, Responder);
uninitialized(info, {catalog_changed, _Method}, _Data) ->
    keep_state_and_data;
uninitialized({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, uninitialized, Data);
uninitialized(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: operational
%%====================================================================

operational(cast, {transport_data, RawData}, Data) ->
    handle_operational_data(RawData, Data, Data#data.responder);
operational(cast, {transport_data, RawData, Responder}, Data) ->
    handle_operational_data(RawData, Data, Responder);
operational(info, {transport_data, RawData}, Data) ->
    handle_operational_data(RawData, Data, Data#data.responder);
operational(info, {transport_data, RawData, Responder}, Data) ->
    handle_operational_data(RawData, Data, Responder);
operational(cast, {resource_updated, Uri}, Data) ->
    handle_resource_updated_cast(Uri, Data);
operational(cast, {emit_log, Level, Logger, LogData}, Data) ->
    handle_emit_log(Level, Logger, LogData, Data);
operational(info, {worker_result, Id, Result}, Data) ->
    handle_worker_result(Id, Result, Data);
operational(info, {'DOWN', Ref, process, Pid, Reason}, Data) ->
    handle_worker_down(Pid, Ref, Reason, Data);
operational(info, {send_notification, _ReqId, Notification}, Data) ->
    send_raw(Data#data.responder, Notification),
    keep_state_and_data;
operational(info, {peer_request, Caller, CallerRef, Method, Params}, Data) ->
    handle_peer_request(Caller, CallerRef, Method, Params, Data);
operational(info, {catalog_changed, Method}, Data) ->
    case Data#data.protocol_version of
        undefined -> ok;
        _ -> send_raw(Data#data.responder,
                      erlmcp_json_rpc:encode_notification(Method, #{}))
    end,
    keep_state_and_data;
operational({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, operational, Data);
operational(EventType, Event, _Data) ->
    ?LOG_DEBUG("session(operational): unmatched event type=~p event=~p",
               [EventType, Event]),
    keep_state_and_data.

%%====================================================================
%% State: shutting_down
%%====================================================================

shutting_down({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, shutting_down, Data);
shutting_down(_EventType, _Event, _Data) ->
    keep_state_and_data.

-spec terminate(term(), atom(), #data{}) -> ok.
terminate(_Reason, _State, #data{server_pid = ServerPid}) ->
    case ServerPid of
        undefined -> ok;
        Pid -> catch erlmcp_server:unregister_session(Pid, self())
    end,
    ok.

%%====================================================================
%% Common call handling (all states)
%%====================================================================

handle_common_call(From, get_state, State, _Data) ->
    {keep_state_and_data, [{reply, From, State}]};
handle_common_call(From, get_instructions, _State, Data) ->
    {keep_state_and_data, [{reply, From, Data#data.instructions}]};
handle_common_call(From, {set_log_level, Level}, _State, Data) ->
    {keep_state, Data#data{log_level = Level}, [{reply, From, ok}]};
handle_common_call(From, _Msg, _State, _Data) ->
    {keep_state_and_data, [{reply, From, {error, unknown_request}}]}.

%%====================================================================
%% Transport data dispatch
%%====================================================================

handle_uninitialized_data(RawData, Data, Responder) ->
    case erlmcp_json_rpc:decode_and_classify(RawData) of
        {ok, Classified} ->
            handle_uninitialized_message(Classified, Data, Responder);
        {error, Reason} ->
            {Code, Msg} = classify_decode_error(Reason),
            send_error(Responder, null, Code, Msg),
            keep_state_and_data
    end.

handle_operational_data(RawData, Data, Responder) ->
    ?LOG_DEBUG("session(operational): raw input ~p", [RawData]),
    case erlmcp_json_rpc:decode_and_classify_any(RawData) of
        {ok, {batch, Items}} ->
            ?LOG_DEBUG("session(operational): batch of ~p items", [length(Items)]),
            handle_batch(Items, Data, Responder);
        {ok, Classified} ->
            ?LOG_DEBUG("session(operational): classified ~p", [Classified]),
            handle_operational_message(Classified, Data, Responder);
        {error, Reason} ->
            ?LOG_DEBUG("session(operational): decode error ~p", [Reason]),
            {Code, Msg} = classify_decode_error(Reason),
            send_error(Responder, null, Code, Msg),
            keep_state_and_data
    end.

handle_batch(Items, Data, Responder) ->
    {Responses, NewData} = lists:foldl(fun(Item, {RespAcc, DAcc}) ->
        case Item of
            {notification, _, _} ->
                {RespAcc, DAcc};
            {parse_error, Reason} ->
                Json = erlmcp_json_rpc:encode_error_response(
                           null, erlmcp_json_rpc:invalid_request(),
                           iolist_to_binary(io_lib:format("~p", [Reason]))),
                {[Json | RespAcc], DAcc};
            {request, Id, Method, Params} ->
                Json = dispatch_batch_request(Id, Method, Params, DAcc),
                {[Json | RespAcc], DAcc};
            {response, Id, Result} ->
                {RespAcc, apply_outbound_response(Id, {ok, Result}, DAcc)};
            {error_response, Id, Error} ->
                {RespAcc, apply_outbound_response(Id, {error, Error}, DAcc)}
        end
    end, {[], Data}, Items),
    case Responses of
        [] -> {keep_state, NewData};
        _ ->
            BatchJson = erlmcp_json_rpc:encode_batch(lists:reverse(Responses)),
            send_raw(Responder, BatchJson),
            {keep_state, NewData}
    end.

dispatch_batch_request(Id, <<"ping">>, _Params, _Data) ->
    erlmcp_json_rpc:encode_response(Id, #{});
dispatch_batch_request(Id, <<"tools/list">>, _Params, Data) ->
    Tools = erlmcp_server:get_tools(Data#data.server_ref),
    ToolList = [format_tool_for_list(T) || T <- maps:values(Tools)],
    erlmcp_json_rpc:encode_response(Id, #{<<"tools">> => ToolList});
dispatch_batch_request(Id, _Method, _Params, _Data) ->
    erlmcp_json_rpc:encode_error_response(Id, erlmcp_json_rpc:method_not_found(),
                                          <<"Method not found">>).

%%====================================================================
%% Message dispatch — uninitialized
%%====================================================================

handle_uninitialized_message({request, Id, <<"initialize">>, Params}, Data, Responder) ->
    handle_initialize(Id, Params, Data, Responder);
handle_uninitialized_message({request, Id, <<"ping">>, _Params}, Data, Responder) ->
    handle_ping(Id, Data, Responder);
handle_uninitialized_message({request, Id, _, _}, Data, Responder) ->
    send_error(Responder, Id, erlmcp_json_rpc:invalid_request(), <<"Server not initialized">>),
    {keep_state, Data};
handle_uninitialized_message({notification, _, _}, _Data, _Responder) ->
    keep_state_and_data;
handle_uninitialized_message(_, _Data, _Responder) ->
    keep_state_and_data.

%%====================================================================
%% Message dispatch — operational
%%====================================================================

handle_operational_message({request, Id, <<"initialize">>, Params}, Data, Responder) ->
    handle_initialize(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"ping">>, _Params}, Data, Responder) ->
    handle_ping(Id, Data, Responder);
handle_operational_message({request, Id, <<"tools/list">>, Params}, Data, Responder) ->
    handle_tools_list(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"tools/call">>, Params}, Data, Responder) ->
    handle_tools_call(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"resources/list">>, Params}, Data, Responder) ->
    handle_resources_list(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"resources/read">>, Params}, Data, Responder) ->
    handle_resources_read(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"resources/templates/list">>, Params}, Data, Responder) ->
    handle_resource_templates_list(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"resources/subscribe">>, Params}, Data, Responder) ->
    handle_resources_subscribe(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"resources/unsubscribe">>, Params}, Data, Responder) ->
    handle_resources_unsubscribe(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"prompts/list">>, Params}, Data, Responder) ->
    handle_prompts_list(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"prompts/get">>, Params}, Data, Responder) ->
    handle_prompts_get(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"logging/setLevel">>, Params}, Data, Responder) ->
    handle_logging_set_level(Id, Params, Data, Responder);
%% Completion
handle_operational_message({request, Id, <<"completion/complete">>, Params}, Data, Responder) ->
    handle_completion_complete(Id, Params, Data, Responder);
%% Tasks
handle_operational_message({request, Id, <<"tasks/get">>, Params}, Data, Responder) ->
    handle_tasks_get(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"tasks/list">>, _Params}, Data, Responder) ->
    handle_tasks_list(Id, Data, Responder);
handle_operational_message({request, Id, <<"tasks/result">>, Params}, Data, Responder) ->
    handle_tasks_result(Id, Params, Data, Responder);
handle_operational_message({request, Id, <<"tasks/cancel">>, Params}, Data, Responder) ->
    handle_tasks_cancel(Id, Params, Data, Responder);
%% Outbound response (client responding to server-initiated request)
handle_operational_message({response, Id, Result}, Data, _Responder) ->
    handle_outbound_response(Id, {ok, Result}, Data);
handle_operational_message({error_response, Id, Error}, Data, _Responder) ->
    handle_outbound_response(Id, {error, Error}, Data);
%% Generic / notifications
handle_operational_message({request, Id, Method, Params}, Data, Responder) ->
    handle_request(Id, Method, Params, Data, Responder);
handle_operational_message({notification, <<"notifications/cancelled">>, Params}, Data, _Responder) ->
    handle_cancelled(Params, Data);
handle_operational_message({notification, <<"notifications/initialized">>, _Params}, _Data, _Responder) ->
    keep_state_and_data;
handle_operational_message(_, _Data, _Responder) ->
    keep_state_and_data.

%%====================================================================
%% Protocol handlers — initialize, ping
%%====================================================================

handle_initialize(Id, Params, Data, Responder) ->
    ClientVersion = maps:get(<<"protocolVersion">>, Params, undefined),
    case erlmcp_capabilities:negotiate_version(
             ClientVersion, erlmcp_capabilities:supported_versions()) of
        {ok, Version} ->
            Instructions = resolve_instructions(Data),
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
            send_response(Responder, Id, Result),
            NewData = Data#data{protocol_version = Version,
                                instructions = Instructions},
            {next_state, operational, NewData};
        {error, no_common_version} ->
            send_error(Responder, Id, erlmcp_json_rpc:invalid_params(),
                       <<"Unsupported protocol version">>),
            keep_state_and_data
    end.

handle_ping(Id, _Data, Responder) ->
    send_response(Responder, Id, #{}),
    keep_state_and_data.

handle_request(Id, Method, Params, Data, Responder) ->
    Session = self(),
    Handlers = erlmcp_server:get_handlers(Data#data.server_ref),
    Ctx = erlmcp_ctx:new(#{
        session => Session,
        request_id => Id,
        server_ref => Data#data.server_ref,
        server_pid => Data#data.server_pid
    }),
    {Pid, Ref} = spawn_monitor(fun() ->
        Result = dispatch_request(Method, Params, Handlers, Ctx),
        _ = Session ! {worker_result, Id, Result}
    end),
    NewPending = maps:put(Id, {Pid, Ref, Responder}, Data#data.pending),
    {keep_state, Data#data{pending = NewPending}}.

handle_cancelled(Params, Data) ->
    RequestId = maps:get(<<"requestId">>, Params, undefined),
    case maps:take(RequestId, Data#data.pending) of
        {{Pid, Ref, _ReplyTo}, NewPending} ->
            demonitor(Ref, [flush]),
            exit(Pid, cancelled),
            {keep_state, Data#data{pending = NewPending}};
        error ->
            keep_state_and_data
    end.

%%====================================================================
%% Tools — list & call (M2a)
%%====================================================================

handle_tools_list(Id, Params, Data, Responder) ->
    Tools = erlmcp_server:get_tools(Data#data.server_ref),
    Sorted = lists:sort(fun(A, B) ->
        maps:get(name, A) =< maps:get(name, B)
    end, maps:values(Tools)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {PageTools, NextCursor} = erlmcp_pagination:paginate(Sorted, Cursor),
    ToolList = [format_tool_for_list(T) || T <- PageTools],
    Result = erlmcp_pagination:paginated_result(<<"tools">>, ToolList, NextCursor),
    send_response(Responder, Id, Result),
    keep_state_and_data.

handle_tools_call(Id, Params, Data, Responder) ->
    case maps:get(<<"name">>, Params, undefined) of
        undefined ->
            send_error(Responder, Id, erlmcp_json_rpc:invalid_params(),
                       <<"Missing tool name">>),
            keep_state_and_data;
        ToolName ->
            Args = maps:get(<<"arguments">>, Params, #{}),
            Meta = maps:get(<<"_meta">>, Params, #{}),
            case erlmcp_server:get_tool(Data#data.server_ref, ToolName) of
                error ->
                    send_error(Responder, Id, erlmcp_json_rpc:invalid_params(),
                               <<"Unknown tool">>),
                    keep_state_and_data;
                {ok, ToolSpec} ->
                    case validate_tool_input(ToolSpec, Args) of
                        ok ->
                            TaskSupport = maps:get(task_support, ToolSpec, forbidden),
                            UseTask = maps:get(<<"_task">>, Meta, false),
                            case TaskSupport =/= forbidden andalso UseTask of
                                true ->
                                    {TaskId, NewData} = start_task(
                                        ToolName, Args, ToolSpec, Meta, Data),
                                    send_response(Responder, Id,
                                        #{<<"taskId">> => TaskId}),
                                    {keep_state, NewData};
                                false ->
                                    dispatch_tool_call(
                                        Id, ToolName, Args, ToolSpec, Meta, Data, Responder)
                            end;
                        {error, _} ->
                            send_error(Responder, Id, erlmcp_json_rpc:invalid_params(),
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

dispatch_tool_call(Id, ToolName, Args, ToolSpec, Meta, Data, Responder) ->
    Session = self(),
    ProgressToken = maps:get(<<"progressToken">>, Meta, undefined),
    RequestMeta = maps:without([<<"progressToken">>, <<"_task">>], Meta),
    CtxOpts = #{session => Session, request_id => Id,
                 server_ref => Data#data.server_ref},
    CtxOpts1 = case ProgressToken of
        undefined -> CtxOpts;
        _ -> CtxOpts#{progress_token => ProgressToken}
    end,
    CtxOpts2 = case maps:size(RequestMeta) of
        0 -> CtxOpts1;
        _ -> CtxOpts1#{meta => RequestMeta}
    end,
    Ctx = erlmcp_ctx:new(CtxOpts2),
    {Pid, Ref} = spawn_monitor(fun() ->
        RawResult = call_tool_handler(ToolName, Args, ToolSpec, Ctx),
        Formatted = format_tool_result(RawResult),
        Result = validate_tool_output(ToolSpec, Formatted),
        _ = Session ! {worker_result, Id, Result}
    end),
    NewPending = maps:put(Id, {Pid, Ref, Responder}, Data#data.pending),
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
format_tool_result({ok, Content, Structured, ResponseMeta})
  when is_list(Content), is_map(Structured), is_map(ResponseMeta) ->
    {ok, #{<<"content">> => Content, <<"structuredContent">> => Structured,
           <<"_meta">> => ResponseMeta}};
format_tool_result({ok, SingleItem, Structured, ResponseMeta})
  when is_map(SingleItem), is_map(Structured), is_map(ResponseMeta) ->
    {ok, #{<<"content">> => [SingleItem], <<"structuredContent">> => Structured,
           <<"_meta">> => ResponseMeta}};
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
%% Resources — list, read, templates, subscribe (M2b)
%%====================================================================

handle_resources_list(Id, Params, Data, Responder) ->
    Resources = erlmcp_server:get_resources(Data#data.server_ref),
    Sorted = lists:sort(fun(A, B) ->
        maps:get(uri, A) =< maps:get(uri, B)
    end, maps:values(Resources)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {Page, NextCursor} = erlmcp_pagination:paginate(Sorted, Cursor),
    ResList = [format_resource_for_list(R) || R <- Page],
    Result = erlmcp_pagination:paginated_result(<<"resources">>, ResList, NextCursor),
    send_response(Responder, Id, Result),
    keep_state_and_data.

handle_resources_read(Id, Params, Data, Responder) ->
    case maps:get(<<"uri">>, Params, undefined) of
        undefined ->
            send_error(Responder, Id, erlmcp_json_rpc:invalid_params(), <<"Missing uri">>),
            keep_state_and_data;
        Uri ->
            Resources = erlmcp_server:get_resources(Data#data.server_ref),
            ResourceTemplates = erlmcp_server:get_resource_templates(Data#data.server_ref),
            case maps:get(Uri, Resources, undefined) of
                undefined ->
                    case erlmcp_uri_template:find_matching(Uri, ResourceTemplates) of
                        {ok, TplSpec, TplParams} ->
                            dispatch_resource_read(Id, Uri, TplSpec, TplParams, Data, Responder);
                        error ->
                            send_error(Responder, Id, -32002, <<"Resource not found">>),
                            keep_state_and_data
                    end;
                ResSpec ->
                    dispatch_resource_read(Id, Uri, ResSpec, #{}, Data, Responder)
            end
    end.

dispatch_resource_read(Id, Uri, Spec, Params, Data, Responder) ->
    Session = self(),
    Ctx = erlmcp_ctx:new(#{session => Session, request_id => Id}),
    {Pid, Ref} = spawn_monitor(fun() ->
        Result = call_resource_handler(Uri, Spec, Params, Ctx),
        _ = Session ! {worker_result, Id, Result}
    end),
    NewPending = maps:put(Id, {Pid, Ref, Responder}, Data#data.pending),
    {keep_state, Data#data{pending = NewPending}}.

call_resource_handler(Uri, Spec, Params, Ctx) ->
    Handler = maps:get(handler, Spec),
    RawResult = case maps:size(Params) of
        0 when is_function(Handler, 1) -> Handler(Ctx);
        0 when is_function(Handler, 2) -> Handler(Uri, Ctx);
        _ when is_function(Handler, 2) -> Handler(Params, Ctx);
        _ when is_function(Handler, 3) -> Handler(Uri, Params, Ctx)
    end,
    case RawResult of
        {ok, Contents} when is_list(Contents) ->
            {ok, #{<<"contents">> => Contents}};
        {ok, SingleContent} when is_map(SingleContent) ->
            {ok, #{<<"contents">> => [SingleContent]}};
        {error, Code, Msg} ->
            {error, Code, Msg}
    end.

handle_resource_templates_list(Id, Params, Data, Responder) ->
    ResourceTemplates = erlmcp_server:get_resource_templates(Data#data.server_ref),
    Sorted = lists:sort(fun(A, B) ->
        maps:get(uri_template, A) =< maps:get(uri_template, B)
    end, maps:values(ResourceTemplates)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {Page, NextCursor} = erlmcp_pagination:paginate(Sorted, Cursor),
    TplList = [format_resource_template_for_list(T) || T <- Page],
    Result = erlmcp_pagination:paginated_result(<<"resourceTemplates">>, TplList, NextCursor),
    send_response(Responder, Id, Result),
    keep_state_and_data.

handle_resources_subscribe(Id, Params, Data, Responder) ->
    Uri = maps:get(<<"uri">>, Params, <<>>),
    NewSubs = maps:put(Uri, true, Data#data.subscriptions),
    send_response(Responder, Id, #{}),
    {keep_state, Data#data{subscriptions = NewSubs}}.

handle_resources_unsubscribe(Id, Params, Data, Responder) ->
    Uri = maps:get(<<"uri">>, Params, <<>>),
    NewSubs = maps:remove(Uri, Data#data.subscriptions),
    send_response(Responder, Id, #{}),
    {keep_state, Data#data{subscriptions = NewSubs}}.

handle_resource_updated_cast(Uri, Data) ->
    case maps:is_key(Uri, Data#data.subscriptions) of
        true ->
            Json = erlmcp_json_rpc:encode_notification(
                       <<"notifications/resources/updated">>, #{<<"uri">> => Uri}),
            send_raw(Data#data.responder, Json);
        false ->
            ok
    end,
    keep_state_and_data.

format_resource_for_list(Spec) ->
    Base = #{<<"uri">> => maps:get(uri, Spec),
             <<"name">> => maps:get(name, Spec, <<>>)},
    B1 = maybe_add_field(<<"description">>, description, Spec, Base),
    maybe_add_field(<<"mimeType">>, mime_type, Spec, B1).

format_resource_template_for_list(Spec) ->
    Base = #{<<"uriTemplate">> => maps:get(uri_template, Spec),
             <<"name">> => maps:get(name, Spec, <<>>)},
    B1 = maybe_add_field(<<"description">>, description, Spec, Base),
    maybe_add_field(<<"mimeType">>, mime_type, Spec, B1).

%%====================================================================
%% Prompts — list & get (M2b)
%%====================================================================

handle_prompts_list(Id, Params, Data, Responder) ->
    Prompts = erlmcp_server:get_prompts(Data#data.server_ref),
    Sorted = lists:sort(fun(A, B) ->
        maps:get(name, A) =< maps:get(name, B)
    end, maps:values(Prompts)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {Page, NextCursor} = erlmcp_pagination:paginate(Sorted, Cursor),
    PromptList = [format_prompt_for_list(P) || P <- Page],
    Result = erlmcp_pagination:paginated_result(<<"prompts">>, PromptList, NextCursor),
    send_response(Responder, Id, Result),
    keep_state_and_data.

handle_prompts_get(Id, Params, Data, Responder) ->
    case maps:get(<<"name">>, Params, undefined) of
        undefined ->
            send_error(Responder, Id, erlmcp_json_rpc:invalid_params(),
                       <<"Missing prompt name">>),
            keep_state_and_data;
        Name ->
            case erlmcp_server:get_prompt(Data#data.server_ref, Name) of
                error ->
                    send_error(Responder, Id, -32003, <<"Prompt not found">>),
                    keep_state_and_data;
                {ok, PromptSpec} ->
                    Args = maps:get(<<"arguments">>, Params, #{}),
                    dispatch_prompt_get(Id, Name, Args, PromptSpec, Data, Responder)
            end
    end.

dispatch_prompt_get(Id, _Name, Args, PromptSpec, Data, Responder) ->
    Session = self(),
    Ctx = erlmcp_ctx:new(#{session => Session, request_id => Id}),
    {Pid, Ref} = spawn_monitor(fun() ->
        Handler = maps:get(handler, PromptSpec),
        Result = case Handler(Args, Ctx) of
            {ok, Messages} when is_list(Messages) ->
                Desc = maps:get(description, PromptSpec, <<>>),
                {ok, #{<<"description">> => Desc, <<"messages">> => Messages}};
            {error, Code, Msg} ->
                {error, Code, Msg}
        end,
        _ = Session ! {worker_result, Id, Result}
    end),
    NewPending = maps:put(Id, {Pid, Ref, Responder}, Data#data.pending),
    {keep_state, Data#data{pending = NewPending}}.

format_prompt_for_list(Spec) ->
    Base = #{<<"name">> => maps:get(name, Spec)},
    B1 = maybe_add_field(<<"description">>, description, Spec, Base),
    case maps:get(arguments, Spec, undefined) of
        undefined -> B1;
        Args ->
            FormattedArgs = [format_prompt_arg(A) || A <- Args],
            B1#{<<"arguments">> => FormattedArgs}
    end.

format_prompt_arg(Arg) when is_map(Arg) ->
    Base = #{<<"name">> => maps:get(name, Arg)},
    B1 = maybe_add_field(<<"description">>, description, Arg, Base),
    case maps:get(required, Arg, false) of
        true -> B1#{<<"required">> => true};
        false -> B1
    end.

%%====================================================================
%% Logging (M2b)
%%====================================================================

handle_logging_set_level(Id, Params, Data, Responder) ->
    LevelBin = maps:get(<<"level">>, Params, <<"emergency">>),
    Level = binary_to_existing_atom(LevelBin, utf8),
    case lists:member(Level, ?LOG_LEVELS) of
        true ->
            send_response(Responder, Id, #{}),
            {keep_state, Data#data{log_level = Level}};
        false ->
            send_error(Responder, Id, erlmcp_json_rpc:invalid_params(),
                       <<"Invalid log level">>),
            keep_state_and_data
    end.

handle_emit_log(Level, Logger, LogData, Data) ->
    case log_level_value(Level) >= log_level_value(Data#data.log_level) of
        true ->
            Params = #{<<"level">> => atom_to_binary(Level, utf8),
                       <<"logger">> => Logger,
                       <<"data">> => LogData},
            Json = erlmcp_json_rpc:encode_notification(
                       <<"notifications/message">>, Params),
            send_raw(Data#data.responder, Json);
        false ->
            ok
    end,
    keep_state_and_data.

log_level_value(debug) -> 0;
log_level_value(info) -> 1;
log_level_value(notice) -> 2;
log_level_value(warning) -> 3;
log_level_value(error) -> 4;
log_level_value(critical) -> 5;
log_level_value(alert) -> 6;
log_level_value(emergency) -> 7.

%%====================================================================
%% Completion (M2b)
%%====================================================================

handle_completion_complete(Id, Params, Data, Responder) ->
    Ref = maps:get(<<"ref">>, Params, #{}),
    RefType = maps:get(<<"type">>, Ref, <<>>),
    Argument = maps:get(<<"argument">>, Params, #{}),
    ArgName = maps:get(<<"name">>, Argument, <<>>),
    ArgValue = maps:get(<<"value">>, Argument, <<>>),
    Values = case RefType of
        <<"ref/prompt">> ->
            PromptName = maps:get(<<"name">>, Ref, <<>>),
            complete_prompt_arg(PromptName, ArgName, ArgValue, Data);
        <<"ref/resource">> ->
            UriTemplate = maps:get(<<"uri">>, Ref, <<>>),
            complete_template_param(UriTemplate, ArgName, ArgValue, Data);
        _ ->
            []
    end,
    Result = #{<<"completion">> => #{
        <<"values">> => Values,
        <<"hasMore">> => false,
        <<"total">> => length(Values)
    }},
    send_response(Responder, Id, Result),
    keep_state_and_data.

complete_prompt_arg(PromptName, ArgName, Prefix, Data) ->
    case erlmcp_server:get_prompt(Data#data.server_ref, PromptName) of
        error -> [];
        {ok, Spec} ->
            Completions = maps:get(completions, Spec, #{}),
            case maps:get(ArgName, Completions, undefined) of
                undefined -> [];
                Fun when is_function(Fun, 1) -> Fun(Prefix)
            end
    end.

complete_template_param(UriTemplate, ArgName, Prefix, Data) ->
    ResourceTemplates = erlmcp_server:get_resource_templates(Data#data.server_ref),
    case maps:get(UriTemplate, ResourceTemplates, undefined) of
        undefined -> [];
        Spec ->
            Completions = maps:get(completions, Spec, #{}),
            case maps:get(ArgName, Completions, undefined) of
                undefined -> [];
                Fun when is_function(Fun, 1) -> Fun(Prefix)
            end
    end.

%%====================================================================
%% Tasks (M6a)
%%====================================================================

handle_tasks_get(Id, Params, Data, Responder) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case maps:get(TaskId, Data#data.tasks, undefined) of
        undefined ->
            send_error(Responder, Id, -32002, <<"Task not found">>),
            keep_state_and_data;
        TaskPid ->
            {ok, Status} = erlmcp_task:get_status(TaskPid),
            send_response(Responder, Id, Status),
            keep_state_and_data
    end.

handle_tasks_list(Id, Data, Responder) ->
    TaskList = maps:fold(fun(_TaskId, TaskPid, Acc) ->
        case is_process_alive(TaskPid) of
            true ->
                {ok, Status} = erlmcp_task:get_status(TaskPid),
                [Status | Acc];
            false ->
                Acc
        end
    end, [], Data#data.tasks),
    send_response(Responder, Id, #{<<"tasks">> => TaskList}),
    keep_state_and_data.

handle_tasks_result(Id, Params, Data, Responder) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case maps:get(TaskId, Data#data.tasks, undefined) of
        undefined ->
            send_error(Responder, Id, -32002, <<"Task not found">>),
            keep_state_and_data;
        TaskPid ->
            case erlmcp_task:get_result(TaskPid) of
                {ok, Result} ->
                    send_response(Responder, Id, Result),
                    keep_state_and_data;
                {error, not_ready} ->
                    send_error(Responder, Id, -32002, <<"Task not ready">>),
                    keep_state_and_data;
                {error, _Reason} ->
                    send_error(Responder, Id, -32603, <<"Task failed">>),
                    keep_state_and_data
            end
    end.

handle_tasks_cancel(Id, Params, Data, Responder) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case maps:get(TaskId, Data#data.tasks, undefined) of
        undefined ->
            send_error(Responder, Id, -32002, <<"Task not found">>),
            keep_state_and_data;
        TaskPid ->
            ok = erlmcp_task:cancel(TaskPid),
            send_response(Responder, Id, #{}),
            keep_state_and_data
    end.

start_task(ToolName, Args, ToolSpec, Meta, Data) ->
    TaskId = generate_task_id(),
    Session = self(),
    ProgressToken = maps:get(<<"progressToken">>, Meta, TaskId),
    Ctx = erlmcp_ctx:new(#{session => Session,
                           request_id => TaskId, progress_token => ProgressToken}),
    Handler = maps:get(handler, ToolSpec, undefined),
    HandlerMod = maps:get(handler_module, ToolSpec, undefined),
    TaskHandler = case Handler of
        Fun when is_function(Fun) -> Fun;
        undefined when HandlerMod =/= undefined ->
            fun(A, C) -> HandlerMod:handle_tool(ToolName, A, C) end
    end,
    {ok, TaskPid} = erlmcp_task_sup:start_task(#{
        id => TaskId,
        session => Session,
        handler => TaskHandler,
        args => Args,
        ctx => Ctx
    }),
    NewTasks = maps:put(TaskId, TaskPid, Data#data.tasks),
    {TaskId, Data#data{tasks = NewTasks}}.

generate_task_id() ->
    Int = erlang:unique_integer([positive]),
    <<"task-", (integer_to_binary(Int))/binary>>.

%%====================================================================
%% Capabilities & instructions
%%====================================================================

resolve_instructions(Data) ->
    case Data#data.server_pid of
        undefined ->
            erlmcp_instructions:generate(
                maps:values(erlmcp_server:get_tools(Data#data.server_ref)));
        ServerPid ->
            case erlmcp_server:get_custom_instructions(ServerPid) of
                undefined ->
                    Identity = erlmcp_server:get_identity(ServerPid),
                    Tools = maps:values(
                        erlmcp_server:get_tools(Data#data.server_ref)),
                    erlmcp_instructions:generate(Identity, Tools);
                Custom when is_binary(Custom) ->
                    Custom
            end
    end.

derive_capabilities(Data) ->
    Base = Data#data.capabilities,
    Tab = Data#data.server_ref,
    Tools = erlmcp_server:get_tools(Tab),
    Resources = erlmcp_server:get_resources(Tab),
    ResourceTemplates = erlmcp_server:get_resource_templates(Tab),
    Prompts = erlmcp_server:get_prompts(Tab),
    B1 = case maps:size(Tools) of
        0 -> Base;
        _ -> Base#{<<"tools">> => #{<<"listChanged">> => true}}
    end,
    B2 = case maps:size(Resources) + maps:size(ResourceTemplates) of
        0 -> B1;
        _ -> B1#{<<"resources">> => #{<<"subscribe">> => true, <<"listChanged">> => true}}
    end,
    B3 = case maps:size(Prompts) of
        0 -> B2;
        _ -> B2#{<<"prompts">> => #{<<"listChanged">> => true}}
    end,
    B4 = B3#{<<"logging">> => #{}, <<"completions">> => #{}},
    HasTasks = lists:any(fun(T) ->
        maps:get(task_support, T, forbidden) =/= forbidden
    end, maps:values(Tools)),
    case HasTasks of
        true -> B4#{<<"tasks">> => #{}};
        false -> B4
    end.

%%====================================================================
%% Peer requests (server→client, M3b)
%%====================================================================

handle_peer_request(Caller, CallerRef, Method, Params, Data) ->
    {Id, NewData} = out_next_id(Data),
    Json = erlmcp_json_rpc:encode_request(Id, Method, Params),
    send_raw(NewData#data.responder, Json),
    OutPending = maps:put(Id, {Caller, CallerRef}, NewData#data.out_pending),
    {keep_state, NewData#data{out_pending = OutPending}}.

handle_outbound_response(Id, Result, Data) ->
    case maps:take(Id, Data#data.out_pending) of
        {{Caller, CallerRef}, NewOutPending} ->
            Caller ! {peer_response, CallerRef, Result},
            {keep_state, Data#data{out_pending = NewOutPending}};
        error ->
            keep_state_and_data
    end.

apply_outbound_response(Id, Result, Data) ->
    case maps:take(Id, Data#data.out_pending) of
        {{Caller, CallerRef}, NewOutPending} ->
            Caller ! {peer_response, CallerRef, Result},
            Data#data{out_pending = NewOutPending};
        error ->
            Data
    end.

out_next_id(#data{out_next_id = Id} = Data) ->
    {Id, Data#data{out_next_id = Id + 1}}.

%%====================================================================
%% Worker completion
%%====================================================================

handle_worker_result(Id, {ok, Result}, Data) ->
    case maps:take(Id, Data#data.pending) of
        {{_Pid, Ref, ReplyTo}, NewPending} ->
            demonitor(Ref, [flush]),
            send_response(ReplyTo, Id, Result),
            {keep_state, Data#data{pending = NewPending}};
        error ->
            keep_state_and_data
    end;
handle_worker_result(Id, {error, Code, Message}, Data) ->
    case maps:take(Id, Data#data.pending) of
        {{_Pid, Ref, ReplyTo}, NewPending} ->
            demonitor(Ref, [flush]),
            send_error(ReplyTo, Id, Code, Message),
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
            {{_P, _R, ReplyTo}, NewPending} = maps:take(Id, Data#data.pending),
            case Reason of
                normal ->
                    {keep_state, Data#data{pending = NewPending}};
                cancelled ->
                    {keep_state, Data#data{pending = NewPending}};
                _ ->
                    send_error(ReplyTo, Id, erlmcp_json_rpc:internal_error(),
                               <<"Internal error">>),
                    {keep_state, Data#data{pending = NewPending}}
            end;
        error ->
            keep_state_and_data
    end.

%%====================================================================
%% Request dispatch (generic handler path)
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

classify_decode_error({invalid_params, _}) ->
    {erlmcp_json_rpc:invalid_params(), <<"Invalid params">>};
classify_decode_error({invalid_request, _}) ->
    {erlmcp_json_rpc:invalid_request(), <<"Invalid request">>};
classify_decode_error(_) ->
    {erlmcp_json_rpc:parse_error(), <<"Parse error">>}.

send_response(undefined, _Id, _Result) ->
    ok;
send_response(Responder, Id, Result) ->
    Json = erlmcp_json_rpc:encode_response(Id, Result),
    erlmcp_reply:send(Responder, Json).

send_error(undefined, _Id, _Code, _Message) ->
    ok;
send_error(Responder, Id, Code, Message) ->
    Json = erlmcp_json_rpc:encode_error_response(Id, Code, Message),
    erlmcp_reply:send(Responder, Json).

send_raw(undefined, _Json) ->
    ok;
send_raw(Responder, Json) ->
    erlmcp_reply:send(Responder, Json).

%%====================================================================
%% Formatting helpers
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
    B4 = case maps:get(icons, Spec, undefined) of
        undefined -> B3;
        Icons -> B3#{<<"icons">> => Icons}
    end,
    B5 = case maps:get(task_support, Spec, undefined) of
        undefined -> B4;
        forbidden -> B4;
        TaskSupport -> B4#{<<"taskSupport">> =>
                           #{<<"supported">> => TaskSupport =/= forbidden}}
    end,
    DiscMeta = disc_meta(Spec),
    case maps:size(DiscMeta) of
        0 -> B5;
        _ -> B5#{<<"_meta">> => DiscMeta}
    end.

disc_meta(Spec) ->
    Base = lists:foldl(fun({ErlKey, JsonKey}, Acc) ->
        case maps:get(ErlKey, Spec, undefined) of
            undefined -> Acc;
            Value -> Acc#{JsonKey => Value}
        end
    end, #{}, [
        {category, <<"io.erlmcp/category">>},
        {when_to_use, <<"io.erlmcp/when_to_use">>},
        {next, <<"io.erlmcp/next">>},
        {entry_point, <<"io.erlmcp/entry_point">>}
    ]),
    case maps:get(protocol_features, Spec, undefined) of
        undefined -> Base;
        PF -> Base#{<<"io.erlmcp/protocol_features">> =>
                     [atom_to_binary(F) || F <- PF]}
    end.

format_annotations(Ann) when is_map(Ann) ->
    maps:fold(fun(Key, Val, Acc) ->
        BinKey = if is_atom(Key) -> atom_to_binary(Key, utf8);
                    is_binary(Key) -> Key
                 end,
        Acc#{BinKey => Val}
    end, #{}, Ann).

maybe_add_field(JsonKey, ErlKey, Spec, Acc) ->
    case maps:get(ErlKey, Spec, undefined) of
        undefined -> Acc;
        Value -> Acc#{JsonKey => Value}
    end.

find_request_by_worker(Pid, Pending) ->
    maps:fold(fun
        (Id, {P, _, _}, error) when P =:= Pid -> {ok, Id};
        (_, _, Acc) -> Acc
    end, error, Pending).
