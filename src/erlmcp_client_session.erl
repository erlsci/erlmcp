-module(erlmcp_client_session).

-behaviour(gen_statem).

%% Core API
-export([start_link/1, initialize/2, ping/1, cancel/2, stop/1]).
%% Tools (M3a-1)
-export([list_tools/1, list_tools/2, call_tool/3, call_tool/4]).
%% Resources (M3a-2..4)
-export([list_resources/1, list_resources/2, read_resource/2,
         list_resource_templates/1, list_resource_templates/2,
         subscribe_resource/2, unsubscribe_resource/2]).
%% Prompts (M3a-5)
-export([list_prompts/1, list_prompts/2, get_prompt/3]).
%% Logging (M3a-6)
-export([set_log_level/2]).
%% Completion (M3a-7)
-export([complete/3]).
%% gen_statem
-export([callback_mode/0, init/1, terminate/3]).
-export([uninitialized/3, operational/3]).

-record(data, {
    transport :: pid(),
    owner :: pid(),
    client_info :: erlmcp_model:peer_info(),
    server_capabilities :: map() | undefined,
    protocol_version :: binary() | undefined,
    next_id = 1 :: pos_integer(),
    pending = #{} :: #{pos_integer() => {pid(), term()}},
    progress_tokens = #{} :: #{binary() | integer() => pid()},
    cancelled = #{} :: #{pos_integer() => true}
}).

%%====================================================================
%% API — core
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
    gen_statem:call(Session, {cancel, RequestId}, 5000).

-spec stop(pid()) -> ok.
stop(Session) ->
    gen_statem:stop(Session).

%%====================================================================
%% API — tools (M3a-1)
%%====================================================================

-spec list_tools(pid()) -> {ok, [map()]} | {error, term()}.
list_tools(Session) ->
    collect_pages(Session, <<"tools">>, <<"tools/list">>, <<"tools">>, #{}).

-spec list_tools(pid(), map()) -> {ok, map()} | {error, term()}.
list_tools(Session, Params) ->
    request(Session, <<"tools">>, <<"tools/list">>, Params).

-spec call_tool(pid(), binary(), map()) -> {ok, map()} | {error, term()}.
call_tool(Session, Name, Args) ->
    call_tool(Session, Name, Args, #{}).

-spec call_tool(pid(), binary(), map(), map()) -> {ok, map()} | {error, term()}.
call_tool(Session, Name, Args, Opts) ->
    Params = #{<<"name">> => Name, <<"arguments">> => Args},
    Params1 = case maps:get(progress_token, Opts, undefined) of
        undefined -> Params;
        Token -> Params#{<<"_meta">> => #{<<"progressToken">> => Token}}
    end,
    request(Session, <<"tools">>, <<"tools/call">>, Params1).

%%====================================================================
%% API — resources (M3a-2..4)
%%====================================================================

-spec list_resources(pid()) -> {ok, [map()]} | {error, term()}.
list_resources(Session) ->
    collect_pages(Session, <<"resources">>, <<"resources/list">>, <<"resources">>, #{}).

-spec list_resources(pid(), map()) -> {ok, map()} | {error, term()}.
list_resources(Session, Params) ->
    request(Session, <<"resources">>, <<"resources/list">>, Params).

-spec read_resource(pid(), binary()) -> {ok, map()} | {error, term()}.
read_resource(Session, Uri) ->
    request(Session, <<"resources">>, <<"resources/read">>, #{<<"uri">> => Uri}).

-spec list_resource_templates(pid()) -> {ok, [map()]} | {error, term()}.
list_resource_templates(Session) ->
    collect_pages(Session, <<"resources">>, <<"resources/templates/list">>,
                  <<"resourceTemplates">>, #{}).

-spec list_resource_templates(pid(), map()) -> {ok, map()} | {error, term()}.
list_resource_templates(Session, Params) ->
    request(Session, <<"resources">>, <<"resources/templates/list">>, Params).

-spec subscribe_resource(pid(), binary()) -> ok | {error, term()}.
subscribe_resource(Session, Uri) ->
    case request(Session, <<"resources">>, <<"resources/subscribe">>,
                 #{<<"uri">> => Uri}) of
        {ok, _} -> ok;
        Error -> Error
    end.

-spec unsubscribe_resource(pid(), binary()) -> ok | {error, term()}.
unsubscribe_resource(Session, Uri) ->
    case request(Session, <<"resources">>, <<"resources/unsubscribe">>,
                 #{<<"uri">> => Uri}) of
        {ok, _} -> ok;
        Error -> Error
    end.

%%====================================================================
%% API — prompts (M3a-5)
%%====================================================================

-spec list_prompts(pid()) -> {ok, [map()]} | {error, term()}.
list_prompts(Session) ->
    collect_pages(Session, <<"prompts">>, <<"prompts/list">>, <<"prompts">>, #{}).

-spec list_prompts(pid(), map()) -> {ok, map()} | {error, term()}.
list_prompts(Session, Params) ->
    request(Session, <<"prompts">>, <<"prompts/list">>, Params).

-spec get_prompt(pid(), binary(), map()) -> {ok, map()} | {error, term()}.
get_prompt(Session, Name, Args) ->
    request(Session, <<"prompts">>, <<"prompts/get">>,
            #{<<"name">> => Name, <<"arguments">> => Args}).

%%====================================================================
%% API — logging (M3a-6)
%%====================================================================

-spec set_log_level(pid(), atom()) -> ok | {error, term()}.
set_log_level(Session, Level) when is_atom(Level) ->
    case request(Session, <<"logging">>, <<"logging/setLevel">>,
                 #{<<"level">> => atom_to_binary(Level, utf8)}) of
        {ok, _} -> ok;
        Error -> Error
    end.

%%====================================================================
%% API — completion (M3a-7)
%%====================================================================

-spec complete(pid(), map(), map()) -> {ok, map()} | {error, term()}.
complete(Session, Ref, Argument) ->
    request(Session, <<"completions">>, <<"completion/complete">>,
            #{<<"ref">> => Ref, <<"argument">> => Argument}).

%%====================================================================
%% gen_statem callbacks
%%====================================================================

callback_mode() ->
    [state_functions].

init(Opts) ->
    process_flag(trap_exit, true),
    Transport = maps:get(transport, Opts),
    Owner = maps:get(owner, Opts, undefined),
    Name = maps:get(name, Opts, <<"erlmcp-client">>),
    Version = maps:get(version, Opts, <<"0.6.0">>),
    Data = #data{
        transport = Transport,
        owner = Owner,
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

operational({call, From}, {request, Cap, Method, Params}, Data) ->
    case check_capability(Cap, Data) of
        ok ->
            {Id, NewData} = next_id(Data),
            send_request(NewData, Id, Method, Params),
            Token = get_progress_token(Params),
            Pending = maps:put(Id, {From, {request, Method}}, NewData#data.pending),
            NewTokens = case Token of
                undefined -> NewData#data.progress_tokens;
                _ -> maps:put(Token, NewData#data.owner, NewData#data.progress_tokens)
            end,
            {keep_state, NewData#data{pending = Pending, progress_tokens = NewTokens}};
        {error, _} = Err ->
            {keep_state_and_data, [{reply, From, Err}]}
    end;

operational({call, From}, {cancel, RequestId}, Data) ->
    Notification = erlmcp_json_rpc:encode_notification(
                       <<"notifications/cancelled">>,
                       #{<<"requestId">> => RequestId}),
    _ = Data#data.transport ! {send, Notification},
    NewCancelled = maps:put(RequestId, true, Data#data.cancelled),
    NewData = case maps:take(RequestId, Data#data.pending) of
        {{CallerFrom, _Type}, NewPending} ->
            gen_statem:reply(CallerFrom, {error, cancelled}),
            Data#data{pending = NewPending, cancelled = NewCancelled};
        error ->
            Data#data{cancelled = NewCancelled}
    end,
    {keep_state, NewData, [{reply, From, ok}]};

operational(cast, {transport_data, RawData}, Data) ->
    case erlmcp_json_rpc:decode_and_classify(RawData) of
        {ok, {response, Id, Result}} ->
            handle_response(Id, {ok, Result}, Data);
        {ok, {error_response, Id, Error}} ->
            handle_response(Id, {error, Error}, Data);
        {ok, {notification, Method, Params}} ->
            handle_notification(Method, Params, Data);
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
            _ = NewData#data.transport ! {send, Initialized},
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
    case maps:is_key(Id, Data#data.cancelled) of
        true ->
            NewCancelled = maps:remove(Id, Data#data.cancelled),
            {keep_state, Data#data{cancelled = NewCancelled}};
        false ->
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
            end
    end.

%%====================================================================
%% Notification handling
%%====================================================================

handle_notification(<<"notifications/progress">>, Params, Data) ->
    Token = maps:get(<<"progressToken">>, Params, undefined),
    _ = case maps:get(Token, Data#data.progress_tokens, undefined) of
        undefined -> ok;
        Caller -> Caller ! {mcp_progress, Token, Params}
    end,
    keep_state_and_data;

handle_notification(<<"notifications/resources/updated">>, Params, Data) ->
    _ = notify_owner({resource_updated, maps:get(<<"uri">>, Params, undefined)}, Data),
    keep_state_and_data;

handle_notification(<<"notifications/message">>, Params, Data) ->
    _ = notify_owner({log_message, Params}, Data),
    keep_state_and_data;

handle_notification(Method, Params, Data) ->
    _ = case is_list_changed(Method) of
        {true, Feature} ->
            notify_owner({list_changed, Feature, Params}, Data);
        false ->
            ok
    end,
    keep_state_and_data.

is_list_changed(<<"notifications/tools/list_changed">>) -> {true, tools};
is_list_changed(<<"notifications/resources/list_changed">>) -> {true, resources};
is_list_changed(<<"notifications/prompts/list_changed">>) -> {true, prompts};
is_list_changed(_) -> false.

notify_owner(Msg, #data{owner = Owner}) when is_pid(Owner) ->
    Owner ! {mcp_notification, Msg};
notify_owner(_, _) ->
    ok.

%%====================================================================
%% Capability gating + request dispatch
%%====================================================================

request(Session, Capability, Method, Params) ->
    gen_statem:call(Session, {request, Capability, Method, Params}, 30000).

get_progress_token(Params) ->
    case maps:get(<<"_meta">>, Params, undefined) of
        undefined -> undefined;
        Meta -> maps:get(<<"progressToken">>, Meta, undefined)
    end.

%%====================================================================
%% Internal
%%====================================================================

next_id(#data{next_id = Id} = Data) ->
    {Id, Data#data{next_id = Id + 1}}.

send_request(#data{transport = Transport}, Id, Method, Params) ->
    Json = erlmcp_json_rpc:encode_request(Id, Method, Params),
    _ = Transport ! {send, Json},
    ok.

check_capability(Cap, #data{server_capabilities = Caps}) when is_map(Caps) ->
    case maps:is_key(Cap, Caps) of
        true -> ok;
        false -> {error, {capability_not_supported, Cap}}
    end;
check_capability(_, _) ->
    {error, not_initialized}.

collect_pages(Session, Cap, Method, Key, Params) ->
    case request(Session, Cap, Method, Params) of
        {ok, Result} ->
            Items = maps:get(Key, Result, []),
            case maps:get(<<"nextCursor">>, Result, undefined) of
                undefined ->
                    {ok, Items};
                Cursor ->
                    case collect_pages(Session, Cap, Method, Key,
                                       #{<<"cursor">> => Cursor}) of
                        {ok, More} -> {ok, Items ++ More};
                        Error -> Error
                    end
            end;
        Error ->
            Error
    end.
