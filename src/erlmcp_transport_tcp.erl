-module(erlmcp_transport_tcp).
-behaviour(gen_server).
-behaviour(erlmcp_transport).

%% Transport behavior callbacks
-export([send/2, close/1]).

%% API
-export([start_link/1, connect/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Types
-type tcp_opts() :: #{
    host := inet:hostname() | inet:ip_address(),
    port := inet:port_number(),
    owner := pid(),
    connect_timeout => timeout(),
    keepalive => boolean(),
    nodelay => boolean(),
    buffer_size => pos_integer()
}.

-type state() :: #{
    socket := gen_tcp:socket() | undefined,
    owner := pid(),
    host := inet:hostname() | inet:ip_address(),
    port := inet:port_number(),
    options := [gen_tcp:connect_option()],
    buffer := binary(),
    connected := boolean(),
    reconnect_timer := reference() | undefined,
    reconnect_attempts := non_neg_integer(),
    max_reconnect_attempts := pos_integer() | infinity
}.

-export_type([tcp_opts/0]).

%% Default values
-define(DEFAULT_CONNECT_TIMEOUT, 5000).
-define(DEFAULT_BUFFER_SIZE, 65536).
-define(INITIAL_RECONNECT_DELAY, 1000).
-define(MAX_RECONNECT_DELAY, 60000).
-define(DEFAULT_MAX_RECONNECT_ATTEMPTS, infinity).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link(tcp_opts()) -> {ok, pid()} | {error, term()}.
start_link(Opts) when is_map(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

-spec connect(pid(), tcp_opts()) -> ok | {error, term()}.
connect(Pid, Opts) when is_pid(Pid), is_map(Opts) ->
    gen_server:call(Pid, {connect, Opts}).

-spec send(pid() | state(), iodata()) -> ok | {error, term()}.
send(Pid, Data) when is_pid(Pid) ->
    gen_server:call(Pid, {send, Data});
send(#{socket := Socket} = _State, Data) when Socket =/= undefined ->
    case gen_tcp:send(Socket, [Data, "\n"]) of
        ok -> ok;
        {error, Reason} -> {error, {tcp_send_failed, Reason}}
    end;
send(_State, _Data) ->
    {error, not_connected}.

-spec close(pid() | state()) -> ok.
close(Pid) when is_pid(Pid) ->
    gen_server:stop(Pid);
close(#{socket := Socket}) when Socket =/= undefined ->
    gen_tcp:close(Socket);
close(_) ->
    ok.

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init(tcp_opts()) -> {ok, state()}.
init(Opts) ->
    process_flag(trap_exit, true),
    
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    Owner = maps:get(owner, Opts),
    
    %% Monitor the owner process
    monitor(process, Owner),
    
    State = #{
        socket => undefined,
        owner => Owner,
        host => Host,
        port => Port,
        options => build_socket_options(Opts),
        buffer => <<>>,
        connected => false,
        reconnect_timer => undefined,
        reconnect_attempts => 0,
        max_reconnect_attempts => maps:get(max_reconnect_attempts, Opts, 
                                          ?DEFAULT_MAX_RECONNECT_ATTEMPTS)
    },
    
    %% Attempt initial connection
    self() ! connect,
    
    {ok, State}.

-spec handle_call(term(), {pid(), term()}, state()) -> 
    {reply, term(), state()} | {noreply, state()}.

handle_call({connect, NewOpts}, _From, State) ->
    %% Update connection parameters
    NewState = State#{
        host := maps:get(host, NewOpts, maps:get(host, State)),
        port := maps:get(port, NewOpts, maps:get(port, State)),
        options := build_socket_options(NewOpts)
    },
    
    %% Disconnect if currently connected
    FinalState = case maps:get(socket, NewState) of
        undefined -> NewState;
        Socket ->
            gen_tcp:close(Socket),
            NewState#{socket := undefined, connected := false}
    end,
    
    %% Trigger reconnection
    self() ! connect,
    
    {reply, ok, FinalState};

handle_call({send, Data}, _From, #{connected := true, socket := Socket} = State) ->
    case gen_tcp:send(Socket, [Data, "\n"]) of
        ok ->
            {reply, ok, State};
        {error, Reason} = Error ->
            logger:error("TCP send failed: ~p", [Reason]),
            %% Connection lost, trigger reconnection
            self() ! {tcp_error, Socket, Reason},
            {reply, Error, State}
    end;

handle_call({send, _Data}, _From, State) ->
    {reply, {error, not_connected}, State};

handle_call(get_state, _From, State) ->
    {reply, {ok, State}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> 
    {noreply, state()} | {stop, term(), state()}.

handle_info(connect, State) ->
    {noreply, attempt_connection(State)};

handle_info({tcp, Socket, Data}, #{socket := Socket, buffer := Buffer} = State) ->
    %% Accumulate data in buffer
    NewBuffer = <<Buffer/binary, Data/binary>>,
    
    %% Process complete messages
    {Messages, RemainingBuffer} = extract_messages(NewBuffer),
    
    %% Send messages to owner
    lists:foreach(fun(Msg) ->
        maps:get(owner, State) ! {transport_message, Msg}
    end, Messages),
    
    {noreply, State#{buffer := RemainingBuffer}};

handle_info({tcp_closed, Socket}, #{socket := Socket} = State) ->
    logger:info("TCP connection closed"),
    {noreply, handle_disconnect(State, normal)};

handle_info({tcp_error, Socket, Reason}, #{socket := Socket} = State) ->
    logger:error("TCP error: ~p", [Reason]),
    {noreply, handle_disconnect(State, Reason)};

handle_info(reconnect, State) ->
    {noreply, attempt_connection(State#{reconnect_timer := undefined})};

handle_info({'DOWN', _MonitorRef, process, Owner, Reason}, 
            #{owner := Owner} = State) ->
    logger:info("Owner process ~p died: ~p", [Owner, Reason]),
    {stop, {owner_died, Reason}, State};

handle_info({'EXIT', Socket, Reason}, #{socket := Socket} = State) ->
    logger:warning("Socket process died: ~p", [Reason]),
    {noreply, handle_disconnect(State, Reason)};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    %% Cancel reconnect timer if active
    cancel_reconnect_timer(State),
    
    %% Close socket if connected
    case maps:get(socket, State, undefined) of
        undefined -> ok;
        Socket -> gen_tcp:close(Socket)
    end,
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

-spec build_socket_options(tcp_opts()) -> [gen_tcp:connect_option()].
build_socket_options(Opts) ->
    BaseOpts = [
        binary,
        {active, true},
        {packet, line},
        {reuseaddr, true},
        {send_timeout, 5000},
        {send_timeout_close, true}
    ],
    
    %% Add optional settings
    OptionalOpts = lists:foldl(fun({Key, OptKey}, Acc) ->
        case maps:get(Key, Opts, undefined) of
            undefined -> Acc;
            Value -> [{OptKey, Value} | Acc]
        end
    end, BaseOpts, [
        {keepalive, keepalive},
        {nodelay, nodelay},
        {buffer_size, buffer}
    ]),
    
    %% Ensure we have appropriate buffer sizes
    BufferSize = maps:get(buffer_size, Opts, ?DEFAULT_BUFFER_SIZE),
    [
        {recbuf, BufferSize},
        {sndbuf, BufferSize}
        | OptionalOpts
    ].

-spec attempt_connection(state()) -> state().
attempt_connection(#{reconnect_attempts := Attempts,
                     max_reconnect_attempts := MaxAttempts} = State)
  when is_integer(MaxAttempts), Attempts >= MaxAttempts ->
    logger:error("Maximum reconnection attempts (~p) reached", [MaxAttempts]),
    State#{connected := false};

attempt_connection(#{host := Host, port := Port, options := Options} = State) ->
    ConnectTimeout = maps:get(connect_timeout, State, ?DEFAULT_CONNECT_TIMEOUT),
    
    logger:info("Attempting TCP connection to ~s:~p", [Host, Port]),
    
    case gen_tcp:connect(Host, Port, Options, ConnectTimeout) of
        {ok, Socket} ->
            logger:info("TCP connection established"),
            %% Notify owner of successful connection
            maps:get(owner, State) ! {transport_connected, self()},
            
            State#{
                socket := Socket,
                connected := true,
                reconnect_attempts := 0,
                buffer := <<>>
            };
        {error, Reason} ->
            logger:error("TCP connection failed: ~p", [Reason]),
            schedule_reconnect(State)
    end.

-spec handle_disconnect(state(), term()) -> state().
handle_disconnect(#{socket := undefined} = State, _Reason) ->
    State;
handle_disconnect(#{socket := Socket} = State, Reason) ->
    %% Close the socket
    catch gen_tcp:close(Socket),
    
    %% Notify owner
    maps:get(owner, State) ! {transport_disconnected, self(), Reason},
    
    %% Schedule reconnection
    NewState = State#{
        socket := undefined,
        connected := false,
        buffer := <<>>
    },
    
    schedule_reconnect(NewState).

-spec schedule_reconnect(state()) -> state().
schedule_reconnect(#{reconnect_timer := Timer} = State) when Timer =/= undefined ->
    %% Already scheduled
    State;
schedule_reconnect(#{reconnect_attempts := Attempts} = State) ->
    %% Calculate backoff delay
    Delay = calculate_backoff(Attempts),
    
    logger:info("Scheduling reconnection in ~p ms (attempt ~p)", 
                [Delay, Attempts + 1]),
    
    Timer = erlang:send_after(Delay, self(), reconnect),
    
    State#{
        reconnect_timer := Timer,
        reconnect_attempts := Attempts + 1
    }.

-spec calculate_backoff(non_neg_integer()) -> pos_integer().
calculate_backoff(Attempts) ->
    %% Exponential backoff with jitter
    BaseDelay = min(?INITIAL_RECONNECT_DELAY * (1 bsl Attempts), 
                    ?MAX_RECONNECT_DELAY),
    Jitter = rand:uniform(BaseDelay div 4),
    BaseDelay + Jitter.

-spec cancel_reconnect_timer(state()) -> ok.
cancel_reconnect_timer(#{reconnect_timer := undefined}) ->
    ok;
cancel_reconnect_timer(#{reconnect_timer := Timer}) ->
    erlang:cancel_timer(Timer),
    ok.

-spec extract_messages(binary()) -> {[binary()], binary()}.
extract_messages(Buffer) ->
    extract_messages(Buffer, []).

-spec extract_messages(binary(), [binary()]) -> {[binary()], binary()}.
extract_messages(Buffer, Acc) ->
    case binary:split(Buffer, <<"\n">>) of
        [_] ->
            %% No complete message
            {lists:reverse(Acc), Buffer};
        [Message, Rest] ->
            %% Found a complete message
            extract_messages(Rest, [Message | Acc])
    end.