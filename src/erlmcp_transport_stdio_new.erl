-module(erlmcp_transport_stdio_new).

-behaviour(gen_server).

%% API exports
-export([start_link/2, send/2, close/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state,
        {transport_id :: atom(),
         server_id :: atom() | undefined,
         reader :: pid() | undefined,
         buffer = <<>> :: binary(),
         test_mode = false :: boolean()}).

-type state() :: #state{}.

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link(atom(), map()) -> {ok, pid()} | {error, term()}.
start_link(TransportId, Config) ->
    gen_server:start_link(?MODULE, [TransportId, Config], []).

-spec send(pid(), iodata()) -> ok | {error, term()}.
send(Transport, Message) when is_pid(Transport) ->
    gen_server:cast(Transport, {send, Message}).

-spec close(pid()) -> ok.
close(Transport) when is_pid(Transport) ->
    gen_server:stop(Transport).

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init([atom() | map()]) -> {ok, state()}.
init([TransportId, Config]) ->
    process_flag(trap_exit, true),

    ServerId = maps:get(server_id, Config, undefined),
    TestMode = is_test_environment(),

    State =
        #state{transport_id = TransportId,
               server_id = ServerId,
               test_mode = TestMode},

    % Only start the reader if we're not in test mode
    case TestMode of
        true ->
            logger:info("Started stdio transport ~p in test mode", [TransportId]),
            {ok, State};
        false ->
            ReaderPid = spawn_link(fun() -> read_loop(self()) end),
            logger:info("Started stdio transport ~p with reader ~p", [TransportId, ReaderPid]),
            {ok, State#state{reader = ReaderPid}}
    end.

-spec handle_call(term(), {pid(), term()}, state()) -> {reply, term(), state()}.
handle_call(get_state, _From, State) ->
    {reply, {ok, State}, State};
handle_call({simulate_input, Line}, _From, #state{test_mode = true} = State) ->
    % Allow tests to simulate input
    handle_message_from_stdin(Line, State),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({send, Message}, State) ->
    % Send message to stdout
    case send_to_stdout(Message) of
        ok ->
            {noreply, State};
        {error, Reason} ->
            logger:error("Failed to send to stdout: ~p", [Reason]),
            {noreply, State}
    end;
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()} | {stop, term(), state()}.
handle_info({line, Line}, State) ->
    handle_message_from_stdin(Line, State),
    {noreply, State};
% Handle responses routed back from server via registry
handle_info({mcp_response, _ServerId, Data}, State) ->
    case send_to_stdout(Data) of
        ok ->
            {noreply, State};
        {error, Reason} ->
            logger:error("Failed to send response to stdout: ~p", [Reason]),
            {noreply, State}
    end;
handle_info({'EXIT', Pid, Reason}, #state{reader = Pid} = State) ->
    case Reason of
        normal ->
            logger:info("Stdin reader finished normally"),
            {noreply, State#state{reader = undefined}};
        _ ->
            logger:error("Stdin reader died: ~p", [Reason]),
            {stop, {reader_died, Reason}, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #state{reader = Reader, transport_id = TransportId}) ->
    logger:info("Stdio transport ~p terminating", [TransportId]),
    case Reader of
        undefined ->
            ok;
        ReaderPid ->
            exit(ReaderPid, shutdown)
    end,
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec handle_message_from_stdin(binary(), state()) -> ok.
handle_message_from_stdin(Line,
                          #state{transport_id = TransportId, server_id = ServerId}) ->
    case ServerId of
        undefined ->
            logger:warning("Transport ~p received message but no server bound", [TransportId]);
        _ ->
            % Route message to server via registry
            erlmcp_registry:route_to_server(ServerId, TransportId, Line)
    end,
    ok.

-spec send_to_stdout(iodata()) -> ok | {error, term()}.
send_to_stdout(Message) ->
    try
        case is_binary(Message) of
            true ->
                io:format("~s~n", [Message]);
            false ->
                io:format("~s~n", [iolist_to_binary(Message)])
        end,
        ok
    catch
        error:Reason ->
            {error, {io_error, Reason}}
    end.

-spec is_test_environment() -> boolean().
is_test_environment() ->
    case get(test_mode) of
        true ->
            true;
        _ ->
            case whereis(eunit_proc) of
                undefined ->
                    false;
                _ ->
                    true
            end
    end.

-spec read_loop(pid()) -> no_return().
read_loop(Parent) ->
    case io:get_line("") of
        eof ->
            logger:info("EOF received, stopping reader"),
            exit(normal);
        {error, Reason} ->
            logger:error("Read error: ~p", [Reason]),
            exit({read_error, Reason});
        Line when is_list(Line) ->
            CleanLine = trim_line(iolist_to_binary(Line)),
            case byte_size(CleanLine) of
                0 ->
                    ok;
                _ ->
                    Parent ! {line, CleanLine},
                    ok
            end,
            read_loop(Parent);
        Line when is_binary(Line) ->
            CleanLine = trim_line(Line),
            case byte_size(CleanLine) of
                0 ->
                    ok;
                _ ->
                    Parent ! {line, CleanLine},
                    ok
            end,
            read_loop(Parent)
    end.

-spec trim_line(binary()) -> binary().
trim_line(Line) ->
    Size = byte_size(Line),
    case Line of
        <<Content:Size/binary>> when Size > 0 ->
            trim_end(Content);
        _ ->
            <<>>
    end.

-spec trim_end(binary()) -> binary().
trim_end(<<>>) ->
    <<>>;
trim_end(Binary) ->
    Size = byte_size(Binary),
    case Binary of
        <<Content:(Size - 2)/binary, "\r\n">> ->
            trim_end(Content);
        <<Content:(Size - 1)/binary, "\n">> ->
            trim_end(Content);
        <<Content:(Size - 1)/binary, "\r">> ->
            trim_end(Content);
        _ ->
            Binary
    end.
