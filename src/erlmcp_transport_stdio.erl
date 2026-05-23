-module(erlmcp_transport_stdio).

-behaviour(gen_server).

%% Transport behaviour callbacks
-export([send/2, close/1]).

%% API
-export([start_link/2, simulate_input/2, validate_config/1]).

%% Testable pure functions
-export([process_raw_input/1, prepare_line/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    transport_id :: erlmcp_transport:transport_id(),
    session :: pid() | undefined,
    reader :: pid() | undefined
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
%% Pure functions (testable without I/O)
%%====================================================================

-spec process_raw_input(term()) -> {deliver, binary()} | eof | {error, term()}.
process_raw_input(eof) ->
    eof;
process_raw_input({error, Reason}) ->
    {error, Reason};
process_raw_input(Line) when is_list(Line) ->
    {deliver, iolist_to_binary(Line)};
process_raw_input(Line) when is_binary(Line) ->
    {deliver, Line}.

-spec prepare_line(binary()) -> {send, binary()} | skip.
prepare_line(RawLine) ->
    case trim_trailing_crlf(RawLine) of
        <<>> -> skip;
        Trimmed -> {send, Trimmed}
    end.

trim_trailing_crlf(<<>>) -> <<>>;
trim_trailing_crlf(Bin) ->
    case binary:last(Bin) of
        $\n -> trim_trailing_crlf(binary:part(Bin, 0, byte_size(Bin) - 1));
        $\r -> trim_trailing_crlf(binary:part(Bin, 0, byte_size(Bin) - 1));
        _ -> Bin
    end.

%%====================================================================
%% gen_server callbacks
%%====================================================================

init({TransportId, Config}) ->
    process_flag(trap_exit, true),
    Session = maps:get(session, Config, undefined),
    ReadFun = maps:get(read_fun, Config, fun default_read/0),
    State = #state{
        transport_id = TransportId,
        session = Session
    },
    case maps:get(test_mode, Config, false) of
        true ->
            {ok, State};
        false ->
            Self = self(),
            ReaderPid = spawn_link(fun() -> read_loop(Self, ReadFun) end),
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

default_read() ->
    io:get_line("").

read_loop(Parent, ReadFun) ->
    case process_raw_input(ReadFun()) of
        eof ->
            exit(normal);
        {error, Reason} ->
            exit({read_error, Reason});
        {deliver, Data} ->
            deliver_line(Parent, Data),
            read_loop(Parent, ReadFun)
    end.

deliver_line(Parent, RawLine) ->
    case prepare_line(RawLine) of
        skip -> ok;
        {send, Trimmed} -> Parent ! {line, Trimmed}, ok
    end.
