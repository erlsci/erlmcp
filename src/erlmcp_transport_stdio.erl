-module(erlmcp_transport_stdio).

-behaviour(gen_server).
-behaviour(erlmcp_transport).

-include_lib("kernel/include/logger.hrl").

%% API (serve/1 and close/1 are the erlmcp_transport behaviour callbacks)
-export([start_link/1, serve/1, close/1, set_session/2,
         simulate_input/2, validate_config/1]).

%% Testable pure functions
-export([process_raw_input/1, prepare_line/1]).

%% gen_server callbacks (init/1 also satisfies erlmcp_transport)
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    session :: pid() | undefined,
    responder :: erlmcp_reply:responder() | undefined,
    reader :: pid() | undefined,
    read_fun :: fun(() -> term()),
    serving = false :: boolean()
}).

%%====================================================================
%% erlmcp_transport behaviour
%%====================================================================

%% init/1 is shared with gen_server — see gen_server callbacks below.

-spec serve(pid()) -> ok | {error, term()}.
serve(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, serve).

-spec close(pid()) -> ok.
close(Pid) when is_pid(Pid) ->
    gen_server:stop(Pid).

%%====================================================================
%% API
%%====================================================================

-spec start_link(erlmcp_transport:config()) -> gen_server:start_ret().
start_link(Config) when is_map(Config) ->
    gen_server:start_link(?MODULE, Config, []).

-spec simulate_input(pid(), binary()) -> ok.
simulate_input(Pid, Line) when is_pid(Pid), is_binary(Line) ->
    gen_server:call(Pid, {simulate_input, Line}).

-spec set_session(pid(), pid()) -> ok.
set_session(Pid, Session) when is_pid(Pid), is_pid(Session) ->
    gen_server:call(Pid, {set_session, Session}).

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

init(Config) ->
    process_flag(trap_exit, true),
    Session = maps:get(session, Config, undefined),
    Responder = case Session of
        undefined -> undefined;
        _ -> erlmcp_reply:new_device(self())
    end,
    ReadFun = maps:get(read_fun, Config, fun default_read/0),
    State = #state{
        session = Session,
        responder = Responder,
        read_fun = ReadFun
    },
    {ok, State}.

handle_call(serve, _From, #state{serving = true} = State) ->
    {reply, {error, already_serving}, State};
handle_call(serve, _From, #state{serving = false} = State) ->
    Self = self(),
    ReaderPid = spawn_link(fun() -> read_loop(Self, State#state.read_fun) end),
    {reply, ok, State#state{reader = ReaderPid, serving = true}};

handle_call({set_session, Session}, _From, State) ->
    Responder = erlmcp_reply:new_device(self()),
    {reply, ok, State#state{session = Session, responder = Responder}};

handle_call({simulate_input, Line}, _From, #state{session = Session,
                                                    responder = Responder} = State)
  when is_pid(Session) ->
    Session ! {transport_data, Line, Responder},
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({send, Data}, State) ->
    _ = write_stdout(Data),
    {noreply, State};

handle_info({line, Line}, #state{session = Session, responder = Responder} = State)
  when is_pid(Session) ->
    Session ! {transport_data, Line, Responder},
    {noreply, State};

handle_info({'EXIT', Pid, normal}, #state{reader = Pid} = State) ->
    {noreply, State#state{reader = undefined}};

handle_info({'EXIT', Pid, Reason}, #state{reader = Pid} = State) ->
    ?LOG_ERROR("stdio reader exited: ~p", [Reason]),
    {stop, {reader_died, Reason}, State};

handle_info(Info, State) ->
    ?LOG_DEBUG("stdio transport: unhandled info ~p", [Info]),
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
        ok = io:put_chars(user, [Data, $\n]),
        ok
    catch
        error:Reason -> {error, {io_error, Reason}}
    end.

default_read() ->
    io:get_line(user, "").

read_loop(Parent, ReadFun) ->
    Raw = ReadFun(),
    case process_raw_input(Raw) of
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
        {send, Trimmed} ->
            Parent ! {line, Trimmed},
            ok
    end.
