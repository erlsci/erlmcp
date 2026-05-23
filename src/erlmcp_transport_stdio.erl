-module(erlmcp_transport_stdio).

-behaviour(gen_server).

%% Transport behaviour callbacks
-export([send/2, close/1]).

%% API
-export([start_link/2, simulate_input/2, validate_config/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    transport_id :: erlmcp_transport:transport_id(),
    session :: pid() | undefined,
    reader :: pid() | undefined,
    test_mode = false :: boolean()
}).

%%====================================================================
%% Transport behaviour
%%====================================================================

-spec send(pid(), iodata()) -> ok | {error, term()}.
send(Pid, Data) when is_pid(Pid) ->
    gen_server:call(Pid, {send, Data}).

-spec close(pid()) -> ok.
close(Pid) when is_pid(Pid) ->
    gen_server:stop(Pid).

%%====================================================================
%% API
%%====================================================================

-spec start_link(erlmcp_transport:transport_id(), erlmcp_transport:config()) ->
    {ok, pid()} | {error, term()}.
start_link(TransportId, Config) when is_atom(TransportId), is_map(Config) ->
    gen_server:start_link(?MODULE, {TransportId, Config}, []).

-spec simulate_input(pid(), binary()) -> ok.
simulate_input(Pid, Line) when is_pid(Pid), is_binary(Line) ->
    gen_server:call(Pid, {simulate_input, Line}).

-spec validate_config(map()) -> ok | {error, term()}.
validate_config(Config) when is_map(Config) ->
    case maps:is_key(session, Config) of
        true -> ok;
        false -> {error, {missing_key, session}}
    end;
validate_config(_) ->
    {error, not_a_map}.

%%====================================================================
%% gen_server callbacks
%%====================================================================

init({TransportId, Config}) ->
    process_flag(trap_exit, true),
    Session = maps:get(session, Config, undefined),
    TestMode = maps:get(test_mode, Config, false),
    State = #state{
        transport_id = TransportId,
        session = Session,
        test_mode = TestMode
    },
    case TestMode of
        true ->
            {ok, State};
        false ->
            Self = self(),
            ReaderPid = spawn_link(fun() -> read_loop(Self) end),
            {ok, State#state{reader = ReaderPid}}
    end.

handle_call({send, Data}, _From, State) ->
    Result = write_stdout(Data),
    {reply, Result, State};

handle_call({simulate_input, Line}, _From, #state{session = Session} = State)
  when is_pid(Session) ->
    Session ! {transport_data, Line},
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({send, Data}, State) ->
    _ = write_stdout(Data),
    {noreply, State};

handle_info({line, Line}, #state{session = Session} = State)
  when is_pid(Session) ->
    Session ! {transport_data, Line},
    {noreply, State};

handle_info({'EXIT', Pid, normal}, #state{reader = Pid} = State) ->
    {noreply, State#state{reader = undefined}};

handle_info({'EXIT', Pid, Reason}, #state{reader = Pid} = State) ->
    logger:error("stdio reader died: ~p", [Reason]),
    {stop, {reader_died, Reason}, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{reader = Pid}) when is_pid(Pid) ->
    exit(Pid, shutdown),
    ok;
terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal
%%====================================================================

-spec write_stdout(iodata()) -> ok | {error, term()}.
write_stdout(Data) ->
    try
        ok = io:put_chars([Data, $\n]),
        ok
    catch
        error:Reason -> {error, {io_error, Reason}}
    end.

-spec read_loop(pid()) -> no_return().
read_loop(Parent) ->
    case io:get_line("") of
        eof ->
            exit(normal);
        {error, Reason} ->
            exit({read_error, Reason});
        Line when is_list(Line) ->
            deliver_line(Parent, iolist_to_binary(Line)),
            read_loop(Parent);
        Line when is_binary(Line) ->
            deliver_line(Parent, Line),
            read_loop(Parent)
    end.

-spec deliver_line(pid(), binary()) -> ok.
deliver_line(Parent, Line) ->
    Trimmed = string:trim(Line, trailing, "\r\n"),
    case Trimmed of
        <<>> -> ok;
        _ -> Parent ! {line, Trimmed}, ok
    end.
