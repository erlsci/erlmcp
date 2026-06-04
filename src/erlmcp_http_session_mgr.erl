-module(erlmcp_http_session_mgr).

-behaviour(gen_server).

-export([start_link/1, mint/1, lookup/2, evict/2,
         set_push_target/3, clear_push_target/2,
         listener_ref/1, get_port/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(session_entry, {
    pid :: pid(),
    mon :: reference(),
    last_activity :: integer(),
    push_relay :: pid(),
    sse_target :: pid() | undefined
}).

-record(state, {
    server_pid :: pid(),
    server_name :: binary(),
    server_version :: binary(),
    idle_timeout :: pos_integer(),
    listener_ref :: term() | undefined,
    sessions = #{} :: #{binary() => #session_entry{}},
    mon_to_id = #{} :: #{reference() => binary()}
}).

-spec start_link(map()) -> gen_server:start_ret().
start_link(Opts) when is_map(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

-spec mint(pid()) -> {ok, binary(), pid()}.
mint(Mgr) ->
    gen_server:call(Mgr, mint).

-spec lookup(pid(), binary()) -> {ok, pid()} | {error, not_found}.
lookup(Mgr, SessionId) when is_binary(SessionId) ->
    gen_server:call(Mgr, {lookup, SessionId}).

-spec evict(pid(), binary()) -> ok.
evict(Mgr, SessionId) when is_binary(SessionId) ->
    gen_server:call(Mgr, {evict, SessionId}).

-spec set_push_target(pid(), binary(), pid()) -> ok.
set_push_target(Mgr, SessionId, TargetPid) when is_binary(SessionId), is_pid(TargetPid) ->
    gen_server:call(Mgr, {set_push_target, SessionId, TargetPid}).

-spec clear_push_target(pid(), binary()) -> ok.
clear_push_target(Mgr, SessionId) when is_binary(SessionId) ->
    gen_server:call(Mgr, {clear_push_target, SessionId}).

-spec listener_ref(pid()) -> term() | undefined.
listener_ref(Mgr) ->
    gen_server:call(Mgr, listener_ref).

-spec get_port(pid()) -> {ok, inet:port_number()} | {error, term()}.
get_port(Mgr) ->
    case listener_ref(Mgr) of
        undefined -> {error, no_listener};
        Ref -> {ok, ranch:get_port(Ref)}
    end.

init(Opts) ->
    process_flag(trap_exit, true),
    ServerPid = maps:get(server_pid, Opts),
    IdleTimeout = maps:get(idle_timeout, Opts, 300000),
    ServerName = maps:get(server_name, Opts, <<"erlmcp">>),
    ServerVersion = maps:get(server_version, Opts, <<"0.6.0">>),
    schedule_gc(IdleTimeout),
    State = #state{
        server_pid = ServerPid,
        server_name = ServerName,
        server_version = ServerVersion,
        idle_timeout = IdleTimeout
    },
    case maps:find(port, Opts) of
        {ok, Port} ->
            EndpointPath = maps:get(endpoint_path, Opts, "/mcp"),
            ReplayBufSize = maps:get(replay_buffer_size, Opts, 100),
            case start_listener(self(), ServerPid, Port,
                                EndpointPath, ReplayBufSize) of
                {ok, LRef} ->
                    {ok, State#state{listener_ref = LRef}};
                {error, Reason} ->
                    {stop, {listener_failed, Reason}}
            end;
        error ->
            {ok, State}
    end.

handle_call(mint, _From, State) ->
    SessionId = generate_session_id(),
    #state{server_pid = ServerPid, server_name = Name,
           server_version = Version} = State,
    Self = self(),
    RelayPid = spawn(fun() -> push_relay_loop(Self, SessionId) end),
    Responder = erlmcp_reply:new_device(RelayPid),
    SessionConfig = #{
        server => ServerPid,
        responder => Responder,
        name => Name,
        version => Version
    },
    case erlmcp_server_session:start_link(SessionConfig) of
        {ok, SessionPid} ->
            Mon = monitor(process, SessionPid),
            Entry = #session_entry{
                pid = SessionPid,
                mon = Mon,
                last_activity = now_ms(),
                push_relay = RelayPid,
                sse_target = undefined
            },
            NewSessions = maps:put(SessionId, Entry, State#state.sessions),
            NewMon = maps:put(Mon, SessionId, State#state.mon_to_id),
            {reply, {ok, SessionId, SessionPid},
             State#state{sessions = NewSessions, mon_to_id = NewMon}};
        {error, _} = Err ->
            exit(RelayPid, shutdown),
            {reply, Err, State}
    end;

handle_call({lookup, SessionId}, _From, State) ->
    case maps:find(SessionId, State#state.sessions) of
        {ok, #session_entry{pid = Pid} = Entry} ->
            Updated = Entry#session_entry{last_activity = now_ms()},
            NewSessions = maps:put(SessionId, Updated, State#state.sessions),
            {reply, {ok, Pid}, State#state{sessions = NewSessions}};
        error ->
            {reply, {error, not_found}, State}
    end;

handle_call({evict, SessionId}, _From, State) ->
    {reply, ok, do_evict(SessionId, State)};

handle_call({set_push_target, SessionId, TargetPid}, _From, State) ->
    case maps:find(SessionId, State#state.sessions) of
        {ok, Entry} ->
            Updated = Entry#session_entry{sse_target = TargetPid},
            NewSessions = maps:put(SessionId, Updated, State#state.sessions),
            {reply, ok, State#state{sessions = NewSessions}};
        error ->
            {reply, ok, State}
    end;

handle_call({clear_push_target, SessionId}, _From, State) ->
    case maps:find(SessionId, State#state.sessions) of
        {ok, Entry} ->
            Updated = Entry#session_entry{sse_target = undefined},
            NewSessions = maps:put(SessionId, Updated, State#state.sessions),
            {reply, ok, State#state{sessions = NewSessions}};
        error ->
            {reply, ok, State}
    end;

handle_call(listener_ref, _From, State) ->
    {reply, State#state.listener_ref, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Mon, process, _Pid, _Reason}, State) ->
    case maps:take(Mon, State#state.mon_to_id) of
        {SessionId, NewMon} ->
            case maps:take(SessionId, State#state.sessions) of
                {#session_entry{push_relay = Relay}, Rest} ->
                    exit(Relay, shutdown),
                    {noreply, State#state{
                        sessions = Rest,
                        mon_to_id = NewMon
                    }};
                error ->
                    {noreply, State#state{mon_to_id = NewMon}}
            end;
        error ->
            {noreply, State}
    end;

handle_info(gc_idle_sessions, State) ->
    Now = now_ms(),
    Timeout = State#state.idle_timeout,
    Expired = maps:fold(fun(SId, #session_entry{last_activity = LA}, Acc) ->
        case Now - LA > Timeout of
            true -> [SId | Acc];
            false -> Acc
        end
    end, [], State#state.sessions),
    NewState = lists:foldl(fun do_evict/2, State, Expired),
    schedule_gc(Timeout),
    {noreply, NewState};

handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State};

handle_info({push_relay, SessionId, Json}, State) ->
    forward_push(SessionId, Json, State),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{listener_ref = LRef} = State) ->
    maps:foreach(fun(_SId, #session_entry{push_relay = Relay}) ->
        exit(Relay, shutdown)
    end, State#state.sessions),
    _ = case LRef of
        undefined -> ok;
        _ -> cowboy:stop_listener(LRef)
    end,
    ok.

%%====================================================================
%% Internal
%%====================================================================

do_evict(SessionId, State) ->
    case maps:take(SessionId, State#state.sessions) of
        {#session_entry{pid = Pid, mon = Mon, push_relay = Relay}, Rest} ->
            demonitor(Mon, [flush]),
            exit(Relay, shutdown),
            catch gen_statem:stop(Pid, normal, 5000),
            State#state{
                sessions = Rest,
                mon_to_id = maps:remove(Mon, State#state.mon_to_id)
            };
        error ->
            State
    end.

start_listener(MgrPid, ServerPid, Port, EndpointPath, ReplayBufSize) ->
    HandlerOpts = #{
        session_mgr => MgrPid,
        server_pid => ServerPid,
        replay_buffer_size => ReplayBufSize
    },
    PathBin = iolist_to_binary(EndpointPath),
    Dispatch = cowboy_router:compile([
        {'_', [{PathBin, erlmcp_http_handler, HandlerOpts}]}
    ]),
    LRef = make_listener_ref(ServerPid),
    TransportOpts = #{socket_opts => [{port, Port}]},
    ProtocolOpts = #{env => #{dispatch => Dispatch}},
    case cowboy:start_clear(LRef, TransportOpts, ProtocolOpts) of
        {ok, _} -> {ok, LRef};
        {error, _} = Err -> Err
    end.

make_listener_ref(ServerPid) ->
    {erlmcp_http, ServerPid}.

generate_session_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    bin_to_hex(Bytes).

bin_to_hex(Bin) ->
    <<<<(hex_digit(H)), (hex_digit(L))>> || <<H:4, L:4>> <= Bin>>.

hex_digit(N) when N < 10 -> N + $0;
hex_digit(N) -> N - 10 + $a.

now_ms() ->
    erlang:monotonic_time(millisecond).

schedule_gc(IdleTimeout) ->
    Interval = max(IdleTimeout div 2, 500),
    erlang:send_after(Interval, self(), gc_idle_sessions).

forward_push(SessionId, Json, State) ->
    case maps:find(SessionId, State#state.sessions) of
        {ok, #session_entry{sse_target = Target}} when is_pid(Target) ->
            Target ! {sse_event, Json},
            ok;
        _ ->
            ok
    end.

push_relay_loop(MgrPid, SessionId) ->
    receive
        {send, Json} ->
            MgrPid ! {push_relay, SessionId, Json},
            push_relay_loop(MgrPid, SessionId)
    end.
