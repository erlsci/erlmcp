-module(erlmcp_client_session).

-behaviour(gen_statem).

-export([start_link/1, initialize/2, ping/1, cancel/2, stop/1]).
-export([callback_mode/0, init/1, terminate/3]).
-export([uninitialized/3, operational/3]).

-record(data, {
    transport :: pid(),
    client_info :: erlmcp_model:peer_info(),
    server_capabilities :: map() | undefined,
    protocol_version :: binary() | undefined,
    next_id = 1 :: pos_integer(),
    pending = #{} :: #{pos_integer() => {pid(), term()}}
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) when is_map(Opts) ->
    gen_statem:start_link(?MODULE, Opts, []).

-spec initialize(pid(), map()) -> {ok, map()} | {error, term()}.
initialize(Session, Params) when is_pid(Session), is_map(Params) ->
    gen_statem:call(Session, {initialize, Params}, 30000).

-spec ping(pid()) -> ok | {error, term()}.
ping(Session) when is_pid(Session) ->
    gen_statem:call(Session, ping, 10000).

-spec cancel(pid(), pos_integer()) -> ok.
cancel(Session, RequestId) when is_pid(Session), is_integer(RequestId) ->
    gen_statem:cast(Session, {cancel, RequestId}).

-spec stop(pid()) -> ok.
stop(Session) ->
    gen_statem:stop(Session).

%%====================================================================
%% gen_statem callbacks
%%====================================================================

callback_mode() ->
    [state_functions].

init(Opts) ->
    process_flag(trap_exit, true),
    Transport = maps:get(transport, Opts),
    Name = maps:get(name, Opts, <<"erlmcp-client">>),
    Version = maps:get(version, Opts, <<"0.6.0">>),
    Data = #data{
        transport = Transport,
        client_info = erlmcp_model:make_client_info(Name, Version)
    },
    {ok, uninitialized, Data}.

%%====================================================================
%% State: uninitialized
%%====================================================================

uninitialized({call, From}, {initialize, Params}, Data) ->
    {Id, NewData} = next_id(Data),
    ClientVersion = maps:get(<<"protocolVersion">>, Params,
                             hd(erlmcp_capabilities:supported_versions())),
    InitParams = #{
        <<"protocolVersion">> => ClientVersion,
        <<"capabilities">> => maps:get(<<"capabilities">>, Params, #{}),
        <<"clientInfo">> => #{
            <<"name">> => erlmcp_model:info_name(Data#data.client_info),
            <<"version">> => erlmcp_model:info_version(Data#data.client_info)
        }
    },
    send_request(NewData, Id, <<"initialize">>, InitParams),
    Pending = maps:put(Id, {From, initialize}, NewData#data.pending),
    {keep_state, NewData#data{pending = Pending}};

uninitialized(cast, {transport_data, RawData}, Data) ->
    case erlmcp_json_rpc:decode_and_classify(RawData) of
        {ok, {response, Id, Result}} ->
            handle_init_response(Id, Result, Data);
        {ok, {error_response, Id, Error}} ->
            handle_init_error(Id, Error, Data);
        _ ->
            keep_state_and_data
    end;

uninitialized({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, uninitialized}]};
uninitialized(_EventType, _Event, _Data) ->
    keep_state_and_data.

%%====================================================================
%% State: operational
%%====================================================================

operational({call, From}, ping, Data) ->
    {Id, NewData} = next_id(Data),
    send_request(NewData, Id, <<"ping">>, #{}),
    Pending = maps:put(Id, {From, ping}, NewData#data.pending),
    {keep_state, NewData#data{pending = Pending}};

operational(cast, {cancel, RequestId}, Data) ->
    Notification = erlmcp_json_rpc:encode_notification(
                       <<"notifications/cancelled">>,
                       #{<<"requestId">> => RequestId}),
    Data#data.transport ! {send, Notification},
    keep_state_and_data;

operational(cast, {transport_data, RawData}, Data) ->
    case erlmcp_json_rpc:decode_and_classify(RawData) of
        {ok, {response, Id, Result}} ->
            handle_response(Id, {ok, Result}, Data);
        {ok, {error_response, Id, Error}} ->
            handle_response(Id, {error, Error}, Data);
        _ ->
            keep_state_and_data
    end;

operational({call, From}, get_state, _Data) ->
    {keep_state_and_data, [{reply, From, operational}]};
operational(_EventType, _Event, _Data) ->
    keep_state_and_data.

terminate(_Reason, _State, _Data) ->
    ok.

%%====================================================================
%% Response handling
%%====================================================================

handle_init_response(Id, Result, Data) ->
    case maps:take(Id, Data#data.pending) of
        {{From, initialize}, NewPending} ->
            Version = maps:get(<<"protocolVersion">>, Result, undefined),
            Caps = maps:get(<<"capabilities">>, Result, #{}),
            NewData = Data#data{
                pending = NewPending,
                protocol_version = Version,
                server_capabilities = Caps
            },
            Initialized = erlmcp_json_rpc:encode_notification(
                              <<"notifications/initialized">>, #{}),
            NewData#data.transport ! {send, Initialized},
            {next_state, operational, NewData,
             [{reply, From, {ok, Result}}]};
        _ ->
            keep_state_and_data
    end.

handle_init_error(Id, Error, Data) ->
    case maps:take(Id, Data#data.pending) of
        {{From, initialize}, NewPending} ->
            {keep_state, Data#data{pending = NewPending},
             [{reply, From, {error, Error}}]};
        _ ->
            keep_state_and_data
    end.

handle_response(Id, Result, Data) ->
    case maps:take(Id, Data#data.pending) of
        {{From, ping}, NewPending} ->
            Reply = case Result of
                {ok, _} -> ok;
                {error, _} = Err -> Err
            end,
            {keep_state, Data#data{pending = NewPending},
             [{reply, From, Reply}]};
        {{From, _Type}, NewPending} ->
            {keep_state, Data#data{pending = NewPending},
             [{reply, From, Result}]};
        error ->
            keep_state_and_data
    end.

%%====================================================================
%% Internal
%%====================================================================

next_id(#data{next_id = Id} = Data) ->
    {Id, Data#data{next_id = Id + 1}}.

send_request(#data{transport = Transport}, Id, Method, Params) ->
    Json = erlmcp_json_rpc:encode_request(Id, Method, Params),
    Transport ! {send, Json},
    ok.
