-module(erlmcp_server_session).

-behaviour(gen_statem).

%% M1 API
-export([start_link/1, send_message/2, get_instructions/1]).
%% Tools (M2a)
-export([register_tool/2, unregister_tool/2, list_tools/1,
         register_handler/2]).
%% Resources (M2b)
-export([register_resource/2, unregister_resource/2, list_resources/1,
         register_resource_template/2, unregister_resource_template/2,
         list_resource_templates/1,
         notify_resource_updated/2]).
%% Prompts (M2b)
-export([register_prompt/2, unregister_prompt/2, list_prompts/1]).
%% Logging (M2b)
-export([set_log_level/2, emit_log/4]).
%% gen_statem
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
    tasks = #{} :: #{binary() => pid()},
    out_pending = #{} :: #{pos_integer() => {pid(), reference()}},
    out_next_id = 1 :: pos_integer(),
    resources = #{} :: #{binary() => map()},
    resource_templates = #{} :: #{binary() => map()},
    prompts = #{} :: #{binary() => map()},
    subscriptions = #{} :: #{binary() => true},
    log_level = emergency :: atom(),
    instructions :: binary() | undefined
}).

-define(LOG_LEVELS, [debug, info, notice, warning, error, critical, alert, emergency]).

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

-spec register_resource(pid(), map()) -> ok.
register_resource(Session, Spec) when is_pid(Session), is_map(Spec) ->
    gen_statem:call(Session, {register_resource, Spec}).

-spec unregister_resource(pid(), binary()) -> ok.
unregister_resource(Session, Uri) when is_pid(Session), is_binary(Uri) ->
    gen_statem:call(Session, {unregister_resource, Uri}).

-spec list_resources(pid()) -> [map()].
list_resources(Session) when is_pid(Session) ->
    gen_statem:call(Session, list_resources).

-spec register_resource_template(pid(), map()) -> ok.
register_resource_template(Session, Spec) when is_pid(Session), is_map(Spec) ->
    gen_statem:call(Session, {register_resource_template, Spec}).

-spec unregister_resource_template(pid(), binary()) -> ok.
unregister_resource_template(Session, UriTemplate) when is_pid(Session), is_binary(UriTemplate) ->
    gen_statem:call(Session, {unregister_resource_template, UriTemplate}).

-spec list_resource_templates(pid()) -> [map()].
list_resource_templates(Session) when is_pid(Session) ->
    gen_statem:call(Session, list_resource_templates).

-spec notify_resource_updated(pid(), binary()) -> ok.
notify_resource_updated(Session, Uri) when is_pid(Session), is_binary(Uri) ->
    gen_statem:cast(Session, {resource_updated, Uri}).

-spec register_prompt(pid(), map()) -> ok.
register_prompt(Session, Spec) when is_pid(Session), is_map(Spec) ->
    gen_statem:call(Session, {register_prompt, Spec}).

-spec unregister_prompt(pid(), binary()) -> ok.
unregister_prompt(Session, Name) when is_pid(Session), is_binary(Name) ->
    gen_statem:call(Session, {unregister_prompt, Name}).

-spec list_prompts(pid()) -> [map()].
list_prompts(Session) when is_pid(Session) ->
    gen_statem:call(Session, list_prompts).

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
    handle_uninitialized_data(RawData, Data);
uninitialized(info, {transport_data, RawData}, Data) ->
    handle_uninitialized_data(RawData, Data);
uninitialized({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, uninitialized, Data);
uninitialized(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: initializing
%%====================================================================

initializing(cast, {transport_data, _RawData}, _Data) ->
    keep_state_and_data;
initializing(info, {transport_data, _RawData}, _Data) ->
    keep_state_and_data;
initializing({call, From}, Msg, Data) ->
    handle_common_call(From, Msg, initializing, Data);
initializing(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: operational
%%====================================================================

operational(cast, {transport_data, RawData}, Data) ->
    handle_operational_data(RawData, Data);
operational(info, {transport_data, RawData}, Data) ->
    handle_operational_data(RawData, Data);
operational(cast, {resource_updated, Uri}, Data) ->
    handle_resource_updated_cast(Uri, Data);
operational(cast, {emit_log, Level, Logger, LogData}, Data) ->
    handle_emit_log(Level, Logger, LogData, Data);
operational(info, {worker_result, Id, Result}, Data) ->
    handle_worker_result(Id, Result, Data);
operational(info, {'DOWN', Ref, process, Pid, Reason}, Data) ->
    handle_worker_down(Pid, Ref, Reason, Data);
operational(info, {send_notification, _ReqId, Notification}, Data) ->
    send_raw(Data, Notification),
    keep_state_and_data;
operational(info, {peer_request, Caller, CallerRef, Method, Params}, Data) ->
    handle_peer_request(Caller, CallerRef, Method, Params, Data);
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
%% Tools
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
%% Resources
handle_common_call(From, {register_resource, Spec}, _State, Data) ->
    do_register_resource(From, Spec, Data);
handle_common_call(From, {unregister_resource, Uri}, _State, Data) ->
    do_unregister_resource(From, Uri, Data);
handle_common_call(From, list_resources, _State, Data) ->
    {keep_state_and_data, [{reply, From, maps:values(Data#data.resources)}]};
handle_common_call(From, {register_resource_template, Spec}, _State, Data) ->
    do_register_resource_template(From, Spec, Data);
handle_common_call(From, {unregister_resource_template, UriT}, _State, Data) ->
    do_unregister_resource_template(From, UriT, Data);
handle_common_call(From, list_resource_templates, _State, Data) ->
    {keep_state_and_data, [{reply, From, maps:values(Data#data.resource_templates)}]};
%% Prompts
handle_common_call(From, {register_prompt, Spec}, _State, Data) ->
    do_register_prompt(From, Spec, Data);
handle_common_call(From, {unregister_prompt, Name}, _State, Data) ->
    do_unregister_prompt(From, Name, Data);
handle_common_call(From, list_prompts, _State, Data) ->
    {keep_state_and_data, [{reply, From, maps:values(Data#data.prompts)}]};
%% Logging
handle_common_call(From, {set_log_level, Level}, _State, Data) ->
    {keep_state, Data#data{log_level = Level}, [{reply, From, ok}]};
%% Catch-all
handle_common_call(From, _Msg, _State, _Data) ->
    {keep_state_and_data, [{reply, From, {error, unknown_request}}]}.

%%====================================================================
%% Transport data dispatch (cast or info — both accepted)
%%====================================================================

handle_uninitialized_data(RawData, Data) ->
    case erlmcp_json_rpc:decode_and_classify(RawData) of
        {ok, Classified} ->
            handle_uninitialized_message(Classified, Data);
        {error, _Reason} ->
            send_error(Data, null, erlmcp_json_rpc:parse_error(), <<"Parse error">>),
            keep_state_and_data
    end.

handle_operational_data(RawData, Data) ->
    case erlmcp_json_rpc:decode_and_classify(RawData) of
        {ok, Classified} ->
            handle_operational_message(Classified, Data);
        {error, _Reason} ->
            send_error(Data, null, erlmcp_json_rpc:parse_error(), <<"Parse error">>),
            keep_state_and_data
    end.

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
%% Tools
handle_operational_message({request, Id, <<"tools/list">>, Params}, Data) ->
    handle_tools_list(Id, Params, Data);
handle_operational_message({request, Id, <<"tools/call">>, Params}, Data) ->
    handle_tools_call(Id, Params, Data);
%% Resources
handle_operational_message({request, Id, <<"resources/list">>, Params}, Data) ->
    handle_resources_list(Id, Params, Data);
handle_operational_message({request, Id, <<"resources/read">>, Params}, Data) ->
    handle_resources_read(Id, Params, Data);
handle_operational_message({request, Id, <<"resources/templates/list">>, Params}, Data) ->
    handle_resource_templates_list(Id, Params, Data);
handle_operational_message({request, Id, <<"resources/subscribe">>, Params}, Data) ->
    handle_resources_subscribe(Id, Params, Data);
handle_operational_message({request, Id, <<"resources/unsubscribe">>, Params}, Data) ->
    handle_resources_unsubscribe(Id, Params, Data);
%% Prompts
handle_operational_message({request, Id, <<"prompts/list">>, Params}, Data) ->
    handle_prompts_list(Id, Params, Data);
handle_operational_message({request, Id, <<"prompts/get">>, Params}, Data) ->
    handle_prompts_get(Id, Params, Data);
%% Logging
handle_operational_message({request, Id, <<"logging/setLevel">>, Params}, Data) ->
    handle_logging_set_level(Id, Params, Data);
%% Completion
handle_operational_message({request, Id, <<"completion/complete">>, Params}, Data) ->
    handle_completion_complete(Id, Params, Data);
%% Tasks
handle_operational_message({request, Id, <<"tasks/get">>, Params}, Data) ->
    handle_tasks_get(Id, Params, Data);
handle_operational_message({request, Id, <<"tasks/list">>, _Params}, Data) ->
    handle_tasks_list(Id, Data);
handle_operational_message({request, Id, <<"tasks/result">>, Params}, Data) ->
    handle_tasks_result(Id, Params, Data);
handle_operational_message({request, Id, <<"tasks/cancel">>, Params}, Data) ->
    handle_tasks_cancel(Id, Params, Data);
%% Outbound response (client responding to server-initiated request)
handle_operational_message({response, Id, Result}, Data) ->
    handle_outbound_response(Id, {ok, Result}, Data);
handle_operational_message({error_response, Id, Error}, Data) ->
    handle_outbound_response(Id, {error, Error}, Data);
%% Generic / notifications
handle_operational_message({request, Id, Method, Params}, Data) ->
    handle_request(Id, Method, Params, Data);
handle_operational_message({notification, <<"notifications/cancelled">>, Params}, Data) ->
    handle_cancelled(Params, Data);
handle_operational_message({notification, <<"notifications/initialized">>, _Params}, _Data) ->
    keep_state_and_data;
handle_operational_message(_, _Data) ->
    keep_state_and_data.

%%====================================================================
%% Protocol handlers — initialize, ping
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
%% Tools — list & call (M2a)
%%====================================================================

handle_tools_list(Id, Params, Data) ->
    Sorted = lists:sort(fun(A, B) ->
        maps:get(name, A) =< maps:get(name, B)
    end, maps:values(Data#data.tools)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {PageTools, NextCursor} = paginate(Sorted, Cursor),
    ToolList = [format_tool_for_list(T) || T <- PageTools],
    Result = paginated_result(<<"tools">>, ToolList, NextCursor),
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
                            TaskSupport = maps:get(task_support, ToolSpec, forbidden),
                            UseTask = maps:get(<<"_task">>, Meta, false),
                            case TaskSupport =/= forbidden andalso UseTask of
                                true ->
                                    {TaskId, NewData} = start_task(
                                        ToolName, Args, ToolSpec, Meta, Data),
                                    send_response(Data, Id,
                                        #{<<"taskId">> => TaskId}),
                                    {keep_state, NewData};
                                false ->
                                    dispatch_tool_call(
                                        Id, ToolName, Args, ToolSpec, Meta, Data)
                            end;
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
%% Resources — list, read, templates, subscribe (M2b)
%%====================================================================

handle_resources_list(Id, Params, Data) ->
    Sorted = lists:sort(fun(A, B) ->
        maps:get(uri, A) =< maps:get(uri, B)
    end, maps:values(Data#data.resources)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {Page, NextCursor} = paginate(Sorted, Cursor),
    ResList = [format_resource_for_list(R) || R <- Page],
    Result = paginated_result(<<"resources">>, ResList, NextCursor),
    send_response(Data, Id, Result),
    keep_state_and_data.

handle_resources_read(Id, Params, Data) ->
    case maps:get(<<"uri">>, Params, undefined) of
        undefined ->
            send_error(Data, Id, erlmcp_json_rpc:invalid_params(), <<"Missing uri">>),
            keep_state_and_data;
        Uri ->
            case maps:get(Uri, Data#data.resources, undefined) of
                undefined ->
                    case find_matching_template(Uri, Data#data.resource_templates) of
                        {ok, TplSpec, TplParams} ->
                            dispatch_resource_read(Id, Uri, TplSpec, TplParams, Data);
                        error ->
                            send_error(Data, Id, -32002, <<"Resource not found">>),
                            keep_state_and_data
                    end;
                ResSpec ->
                    dispatch_resource_read(Id, Uri, ResSpec, #{}, Data)
            end
    end.

dispatch_resource_read(Id, Uri, Spec, Params, Data) ->
    Session = self(),
    Ctx = erlmcp_ctx:new(#{session => Session, transport => Data#data.transport,
                           request_id => Id}),
    {Pid, Ref} = spawn_monitor(fun() ->
        Result = call_resource_handler(Uri, Spec, Params, Ctx),
        _ = Session ! {worker_result, Id, Result}
    end),
    NewPending = maps:put(Id, {Pid, Ref}, Data#data.pending),
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

handle_resource_templates_list(Id, Params, Data) ->
    Sorted = lists:sort(fun(A, B) ->
        maps:get(uri_template, A) =< maps:get(uri_template, B)
    end, maps:values(Data#data.resource_templates)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {Page, NextCursor} = paginate(Sorted, Cursor),
    TplList = [format_resource_template_for_list(T) || T <- Page],
    Result = paginated_result(<<"resourceTemplates">>, TplList, NextCursor),
    send_response(Data, Id, Result),
    keep_state_and_data.

handle_resources_subscribe(Id, Params, Data) ->
    Uri = maps:get(<<"uri">>, Params, <<>>),
    NewSubs = maps:put(Uri, true, Data#data.subscriptions),
    send_response(Data, Id, #{}),
    {keep_state, Data#data{subscriptions = NewSubs}}.

handle_resources_unsubscribe(Id, Params, Data) ->
    Uri = maps:get(<<"uri">>, Params, <<>>),
    NewSubs = maps:remove(Uri, Data#data.subscriptions),
    send_response(Data, Id, #{}),
    {keep_state, Data#data{subscriptions = NewSubs}}.

handle_resource_updated_cast(Uri, Data) ->
    case maps:is_key(Uri, Data#data.subscriptions) of
        true ->
            Json = erlmcp_json_rpc:encode_notification(
                       <<"notifications/resources/updated">>, #{<<"uri">> => Uri}),
            send_raw(Data, Json);
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
%% Resources — URI template matching
%%====================================================================

find_matching_template(Uri, Templates) ->
    maps:fold(fun(UriTemplate, Spec, error) ->
        case match_template(UriTemplate, Uri) of
            {ok, Params} -> {ok, Spec, Params};
            error -> error
        end;
    (_UriTemplate, _Spec, Found) -> Found
    end, error, Templates).

match_template(Template, Uri) ->
    TParts = binary:split(Template, <<"/">>, [global]),
    UParts = binary:split(Uri, <<"/">>, [global]),
    case length(TParts) =:= length(UParts) of
        false -> error;
        true -> match_parts(TParts, UParts, #{})
    end.

match_parts([], [], Acc) -> {ok, Acc};
match_parts([TPart | TRest], [UPart | URest], Acc) ->
    case TPart of
        <<"{", Rest/binary>> ->
            case binary:split(Rest, <<"}">>) of
                [ParamName, <<>>] ->
                    match_parts(TRest, URest, Acc#{ParamName => UPart});
                _ -> error
            end;
        UPart ->
            match_parts(TRest, URest, Acc);
        _ -> error
    end.

%%====================================================================
%% Prompts — list & get (M2b)
%%====================================================================

handle_prompts_list(Id, Params, Data) ->
    Sorted = lists:sort(fun(A, B) ->
        maps:get(name, A) =< maps:get(name, B)
    end, maps:values(Data#data.prompts)),
    Cursor = maps:get(<<"cursor">>, Params, undefined),
    {Page, NextCursor} = paginate(Sorted, Cursor),
    PromptList = [format_prompt_for_list(P) || P <- Page],
    Result = paginated_result(<<"prompts">>, PromptList, NextCursor),
    send_response(Data, Id, Result),
    keep_state_and_data.

handle_prompts_get(Id, Params, Data) ->
    case maps:get(<<"name">>, Params, undefined) of
        undefined ->
            send_error(Data, Id, erlmcp_json_rpc:invalid_params(),
                       <<"Missing prompt name">>),
            keep_state_and_data;
        Name ->
            case maps:get(Name, Data#data.prompts, undefined) of
                undefined ->
                    send_error(Data, Id, -32003, <<"Prompt not found">>),
                    keep_state_and_data;
                PromptSpec ->
                    Args = maps:get(<<"arguments">>, Params, #{}),
                    dispatch_prompt_get(Id, Name, Args, PromptSpec, Data)
            end
    end.

dispatch_prompt_get(Id, _Name, Args, PromptSpec, Data) ->
    Session = self(),
    Ctx = erlmcp_ctx:new(#{session => Session, transport => Data#data.transport,
                           request_id => Id}),
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
    NewPending = maps:put(Id, {Pid, Ref}, Data#data.pending),
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

handle_logging_set_level(Id, Params, Data) ->
    LevelBin = maps:get(<<"level">>, Params, <<"emergency">>),
    Level = binary_to_existing_atom(LevelBin, utf8),
    case lists:member(Level, ?LOG_LEVELS) of
        true ->
            send_response(Data, Id, #{}),
            {keep_state, Data#data{log_level = Level}};
        false ->
            send_error(Data, Id, erlmcp_json_rpc:invalid_params(),
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
            send_raw(Data, Json);
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

handle_completion_complete(Id, Params, Data) ->
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
    send_response(Data, Id, Result),
    keep_state_and_data.

complete_prompt_arg(PromptName, ArgName, Prefix, Data) ->
    case maps:get(PromptName, Data#data.prompts, undefined) of
        undefined -> [];
        Spec ->
            Completions = maps:get(completions, Spec, #{}),
            case maps:get(ArgName, Completions, undefined) of
                undefined -> [];
                Fun when is_function(Fun, 1) -> Fun(Prefix)
            end
    end.

complete_template_param(UriTemplate, ArgName, Prefix, Data) ->
    case maps:get(UriTemplate, Data#data.resource_templates, undefined) of
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

handle_tasks_get(Id, Params, Data) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case maps:get(TaskId, Data#data.tasks, undefined) of
        undefined ->
            send_error(Data, Id, -32002, <<"Task not found">>),
            keep_state_and_data;
        TaskPid ->
            {ok, Status} = erlmcp_task:get_status(TaskPid),
            send_response(Data, Id, Status),
            keep_state_and_data
    end.

handle_tasks_list(Id, Data) ->
    TaskList = maps:fold(fun(_TaskId, TaskPid, Acc) ->
        case is_process_alive(TaskPid) of
            true ->
                {ok, Status} = erlmcp_task:get_status(TaskPid),
                [Status | Acc];
            false ->
                Acc
        end
    end, [], Data#data.tasks),
    send_response(Data, Id, #{<<"tasks">> => TaskList}),
    keep_state_and_data.

handle_tasks_result(Id, Params, Data) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case maps:get(TaskId, Data#data.tasks, undefined) of
        undefined ->
            send_error(Data, Id, -32002, <<"Task not found">>),
            keep_state_and_data;
        TaskPid ->
            case erlmcp_task:get_result(TaskPid) of
                {ok, Result} ->
                    send_response(Data, Id, Result),
                    keep_state_and_data;
                {error, not_ready} ->
                    send_error(Data, Id, -32002, <<"Task not ready">>),
                    keep_state_and_data;
                {error, _Reason} ->
                    send_error(Data, Id, -32603, <<"Task failed">>),
                    keep_state_and_data
            end
    end.

handle_tasks_cancel(Id, Params, Data) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case maps:get(TaskId, Data#data.tasks, undefined) of
        undefined ->
            send_error(Data, Id, -32002, <<"Task not found">>),
            keep_state_and_data;
        TaskPid ->
            ok = erlmcp_task:cancel(TaskPid),
            send_response(Data, Id, #{}),
            keep_state_and_data
    end.

start_task(ToolName, Args, ToolSpec, Meta, Data) ->
    TaskId = generate_task_id(),
    Session = self(),
    Transport = Data#data.transport,
    ProgressToken = maps:get(<<"progressToken">>, Meta, TaskId),
    Ctx = erlmcp_ctx:new(#{session => Session, transport => Transport,
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
%% Registration — tools (M2a)
%%====================================================================

do_register_tool(From, ToolSpec, Data) ->
    Name = maps:get(name, ToolSpec),
    NewTools = maps:put(Name, ToolSpec, Data#data.tools),
    NewData = Data#data{tools = NewTools},
    maybe_notify(<<"notifications/tools/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

do_unregister_tool(From, ToolName, Data) ->
    NewTools = maps:remove(ToolName, Data#data.tools),
    NewData = Data#data{tools = NewTools},
    maybe_notify(<<"notifications/tools/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

do_register_handler(From, Module, Data) ->
    ToolSpecs = Module:tools(),
    NewTools = lists:foldl(fun(Spec, Acc) ->
        Name = maps:get(name, Spec),
        maps:put(Name, Spec#{handler_module => Module}, Acc)
    end, Data#data.tools, ToolSpecs),
    NewData = Data#data{tools = NewTools},
    maybe_notify(<<"notifications/tools/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

%%====================================================================
%% Registration — resources (M2b)
%%====================================================================

do_register_resource(From, Spec, Data) ->
    Uri = maps:get(uri, Spec),
    NewRes = maps:put(Uri, Spec, Data#data.resources),
    NewData = Data#data{resources = NewRes},
    maybe_notify(<<"notifications/resources/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

do_unregister_resource(From, Uri, Data) ->
    NewRes = maps:remove(Uri, Data#data.resources),
    NewSubs = maps:remove(Uri, Data#data.subscriptions),
    NewData = Data#data{resources = NewRes, subscriptions = NewSubs},
    maybe_notify(<<"notifications/resources/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

do_register_resource_template(From, Spec, Data) ->
    UriT = maps:get(uri_template, Spec),
    NewTpls = maps:put(UriT, Spec, Data#data.resource_templates),
    NewData = Data#data{resource_templates = NewTpls},
    maybe_notify(<<"notifications/resources/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

do_unregister_resource_template(From, UriT, Data) ->
    NewTpls = maps:remove(UriT, Data#data.resource_templates),
    NewData = Data#data{resource_templates = NewTpls},
    maybe_notify(<<"notifications/resources/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

%%====================================================================
%% Registration — prompts (M2b)
%%====================================================================

do_register_prompt(From, Spec, Data) ->
    Name = maps:get(name, Spec),
    NewPrompts = maps:put(Name, Spec, Data#data.prompts),
    NewData = Data#data{prompts = NewPrompts},
    maybe_notify(<<"notifications/prompts/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

do_unregister_prompt(From, Name, Data) ->
    NewPrompts = maps:remove(Name, Data#data.prompts),
    NewData = Data#data{prompts = NewPrompts},
    maybe_notify(<<"notifications/prompts/list_changed">>, NewData),
    {keep_state, NewData, [{reply, From, ok}]}.

%%====================================================================
%% Capabilities & instructions
%%====================================================================

derive_capabilities(Data) ->
    Base = Data#data.capabilities,
    B1 = case maps:size(Data#data.tools) of
        0 -> Base;
        _ -> Base#{<<"tools">> => #{<<"listChanged">> => true}}
    end,
    B2 = case maps:size(Data#data.resources) + maps:size(Data#data.resource_templates) of
        0 -> B1;
        _ -> B1#{<<"resources">> => #{<<"subscribe">> => true, <<"listChanged">> => true}}
    end,
    B3 = case maps:size(Data#data.prompts) of
        0 -> B2;
        _ -> B2#{<<"prompts">> => #{<<"listChanged">> => true}}
    end,
    B4 = B3#{<<"logging">> => #{}, <<"completions">> => #{}},
    HasTasks = lists:any(fun(T) ->
        maps:get(task_support, T, forbidden) =/= forbidden
    end, maps:values(Data#data.tools)),
    case HasTasks of
        true -> B4#{<<"tasks">> => #{}};
        false -> B4
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
%% Peer requests (server→client, M3b)
%%====================================================================

handle_peer_request(Caller, CallerRef, Method, Params, Data) ->
    {Id, NewData} = out_next_id(Data),
    Json = erlmcp_json_rpc:encode_request(Id, Method, Params),
    send_raw(NewData, Json),
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

out_next_id(#data{out_next_id = Id} = Data) ->
    {Id, Data#data{out_next_id = Id + 1}}.

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

maybe_notify(_Method, #data{protocol_version = undefined}) ->
    ok;
maybe_notify(Method, Data) ->
    Json = erlmcp_json_rpc:encode_notification(Method, #{}),
    send_raw(Data, Json).

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
    B4 = case maps:get(task_support, Spec, undefined) of
        undefined -> B3;
        TaskSupport -> B3#{<<"taskSupport">> => atom_to_binary(TaskSupport, utf8)}
    end,
    Meta = build_meta(Spec),
    case maps:size(Meta) of
        0 -> B4;
        _ -> B4#{<<"_meta">> => Meta}
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

maybe_add_field(JsonKey, AtomKey, Spec, Map) ->
    case maps:get(AtomKey, Spec, undefined) of
        undefined -> Map;
        Value -> Map#{JsonKey => Value}
    end.

%%====================================================================
%% Pagination (shared: tools, resources, templates, prompts)
%%====================================================================

paginate(Items, undefined) ->
    paginate_from(Items, 0, 50);
paginate(Items, Cursor) ->
    Offset = binary_to_integer(base64:decode(Cursor)),
    paginate_from(Items, Offset, 50).

paginate_from(Items, Offset, PageSize) ->
    Remaining = lists:nthtail(min(Offset, length(Items)), Items),
    case length(Remaining) > PageSize of
        true ->
            Page = lists:sublist(Remaining, PageSize),
            NextCursor = base64:encode(integer_to_binary(Offset + PageSize)),
            {Page, NextCursor};
        false ->
            {Remaining, undefined}
    end.

paginated_result(Key, Items, undefined) ->
    #{Key => Items};
paginated_result(Key, Items, NextCursor) ->
    #{Key => Items, <<"nextCursor">> => NextCursor}.

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
