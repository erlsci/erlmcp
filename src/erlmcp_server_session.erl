-module(erlmcp_server_session).

-behaviour(gen_statem).

-export([start_link/1, send_message/2]).
-export([callback_mode/0, init/1, terminate/3]).
-export([uninitialized/3, initializing/3, operational/3, shutting_down/3]).

-record(data, {
    transport :: pid() | undefined,
    server_info :: erlmcp_model:peer_info(),
    capabilities :: map(),
    protocol_version :: binary() | undefined,
    next_id = 1 :: pos_integer(),
    pending = #{} :: #{pos_integer() => {pid(), reference()}},
    handlers :: map()
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
uninitialized({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, uninitialized}]};
uninitialized(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: initializing (brief — transitions to operational on success)
%%====================================================================

initializing(cast, {transport_data, _RawData}, _Data) ->
    keep_state_and_data;
initializing({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, initializing}]};
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
operational({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, operational}]};
operational(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: shutting_down
%%====================================================================

shutting_down({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, shutting_down}]};
shutting_down(_EventType, _Event, _Data) ->
    keep_state_and_data.

-spec terminate(term(), atom(), #data{}) -> ok.
terminate(_Reason, _State, _Data) ->
    ok.

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
            ServerCaps = erlmcp_capabilities:build_server_capabilities(
                             Data#data.capabilities),
            Result = #{
                <<"protocolVersion">> => Version,
                <<"capabilities">> => ServerCaps,
                <<"serverInfo">> => #{
                    <<"name">> => erlmcp_model:info_name(Data#data.server_info),
                    <<"version">> => erlmcp_model:info_version(Data#data.server_info)
                }
            },
            send_response(Data, Id, Result),
            {next_state, operational, Data#data{protocol_version = Version}};
        {error, no_common_version} ->
            send_error(Data, Id, erlmcp_json_rpc:invalid_params(), <<"Unsupported protocol version">>),
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
                    send_error(Data, Id, erlmcp_json_rpc:internal_error(), <<"Internal error">>),
                    {keep_state, Data#data{pending = NewPending}}
            end;
        error ->
            keep_state_and_data
    end.

%%====================================================================
%% Request dispatch
%%====================================================================

dispatch_request(Method, Params, Handlers, _Ctx) ->
    case maps:get(Method, Handlers, undefined) of
        undefined ->
            {error, erlmcp_json_rpc:method_not_found(), <<"Method not found">>};
        Handler when is_function(Handler, 2) ->
            Handler(Params, _Ctx);
        {Mod, Fun} ->
            Mod:Fun(Params, _Ctx)
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
