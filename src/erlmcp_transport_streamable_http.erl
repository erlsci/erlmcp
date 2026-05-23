-module(erlmcp_transport_streamable_http).

-behaviour(gen_server).

-export([start_link/1, start_link/2, send/2, close/1, validate_config/1,
         simulate_request/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    transport_id :: atom() | undefined,
    session :: pid() | undefined,
    listen_socket :: gen_tcp:socket() | undefined,
    connections = [] :: [gen_tcp:socket()],
    port :: inet:port_number(),
    pending_responses = #{} :: #{reference() => gen_tcp:socket()},
    test_mode = false :: boolean()
}).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) when is_map(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

-spec start_link(atom(), map()) -> {ok, pid()} | {error, term()}.
start_link(TransportId, Opts) when is_atom(TransportId), is_map(Opts) ->
    gen_server:start_link(?MODULE, Opts#{transport_id => TransportId}, []).

-spec send(pid(), iodata()) -> ok | {error, term()}.
send(Pid, Data) when is_pid(Pid) ->
    gen_server:call(Pid, {send, Data}).

-spec close(pid()) -> ok.
close(Pid) when is_pid(Pid) ->
    gen_server:stop(Pid).

-spec validate_config(map()) -> ok | {error, term()}.
validate_config(Config) when is_map(Config) ->
    case maps:is_key(session, Config) of
        true -> ok;
        false ->
            case maps:is_key(port, Config) of
                true -> ok;
                false -> {error, {missing_key, session_or_port}}
            end
    end;
validate_config(_) ->
    {error, not_a_map}.

-spec simulate_request(pid(), binary()) -> ok.
simulate_request(Pid, Data) when is_pid(Pid), is_binary(Data) ->
    gen_server:call(Pid, {simulate_request, Data}).

init(Opts) ->
    process_flag(trap_exit, true),
    Session = maps:get(session, Opts, undefined),
    TestMode = maps:get(test_mode, Opts, false),
    Port = maps:get(port, Opts, 0),
    TransportId = maps:get(transport_id, Opts, undefined),
    State = #state{
        transport_id = TransportId,
        session = Session,
        port = Port,
        test_mode = TestMode
    },
    case TestMode of
        true ->
            {ok, State};
        false ->
            case gen_tcp:listen(Port, [binary, {active, true},
                                       {reuseaddr, true}, {packet, http_bin}]) of
                {ok, ListenSocket} ->
                    self() ! accept,
                    {ok, State#state{listen_socket = ListenSocket}};
                {error, Reason} ->
                    {stop, {listen_failed, Reason}}
            end
    end.

handle_call({send, _Data}, _From, #state{test_mode = true} = State) ->
    {reply, ok, State};
handle_call({send, Data}, _From, #state{connections = [Conn | _]} = State) ->
    Response = build_http_response(Data),
    _ = gen_tcp:send(Conn, Response),
    {reply, ok, State};
handle_call({send, _Data}, _From, State) ->
    {reply, {error, no_connection}, State};

handle_call({simulate_request, Data}, _From,
            #state{session = Session, test_mode = true} = State)
  when is_pid(Session) ->
    Session ! {transport_data, Data},
    {reply, ok, State};
handle_call({simulate_request, _Data}, _From, State) ->
    {reply, {error, no_session}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(accept, #state{listen_socket = LSock} = State) when LSock =/= undefined ->
    case gen_tcp:accept(LSock, 100) of
        {ok, Socket} ->
            self() ! accept,
            {noreply, State#state{connections = [Socket | State#state.connections]}};
        {error, timeout} ->
            self() ! accept,
            {noreply, State};
        {error, _Reason} ->
            {noreply, State}
    end;

handle_info({http, Socket, {http_request, 'POST', _, _}}, State) ->
    _ = inet:setopts(Socket, [{active, true}]),
    {noreply, State};

handle_info({http, Socket, {http_header, _, _, _, _}}, State) ->
    _ = inet:setopts(Socket, [{active, true}]),
    {noreply, State};

handle_info({http, Socket, http_eoh}, State) ->
    _ = inet:setopts(Socket, [{active, true}, {packet, raw}]),
    {noreply, State};

handle_info({tcp, _Socket, Data}, #state{session = Session} = State)
  when is_pid(Session) ->
    Session ! {transport_data, Data},
    {noreply, State};

handle_info({tcp_closed, Socket}, State) ->
    NewConns = lists:delete(Socket, State#state.connections),
    {noreply, State#state{connections = NewConns}};

handle_info({send, Data}, State) ->
    _ = handle_call({send, Data}, undefined, State),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{listen_socket = LSock, connections = Conns}) ->
    lists:foreach(fun(S) -> catch gen_tcp:close(S) end, Conns),
    case LSock of
        undefined -> ok;
        _ -> gen_tcp:close(LSock)
    end,
    ok.

build_http_response(Body) ->
    BinBody = iolist_to_binary(Body),
    Len = integer_to_binary(byte_size(BinBody)),
    [<<"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ">>,
     Len, <<"\r\n\r\n">>, BinBody].
