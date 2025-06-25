-module(erlmcp_transport_stdio).
-behaviour(gen_server).

%% API exports
-export([send/2, start_link/1, close/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    owner :: pid(),
    reader :: pid() | undefined,
    buffer = <<>> :: binary()
}).

-type state() :: #state{}.

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link(pid()) -> {ok, pid()} | {error, term()}.
start_link(Owner) when is_pid(Owner) ->
    gen_server:start_link(?MODULE, [Owner], []).

-spec send(pid() | term(), iodata()) -> ok | {error, term()}.
send(_TransportState, Message) ->
    try
        io:format("~s~n", [Message]),
        ok
    catch
        error:Reason ->
            {error, {io_error, Reason}}
    end.

-spec close(pid() | term()) -> ok.
close(Pid) when is_pid(Pid) ->
    gen_server:stop(Pid);
close(_) ->
    ok.

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init([pid()]) -> {ok, state()}.
init([Owner]) ->
    process_flag(trap_exit, true),
    ReaderPid = spawn_link(fun() -> read_loop(self(), Owner) end),
    {ok, #state{owner = Owner, reader = ReaderPid}}.

-spec handle_call(term(), {pid(), term()}, state()) -> {reply, ok, state()}.
handle_call(get_state, _From, State) ->
    {reply, {ok, State}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()} | {stop, term(), state()}.
handle_info({line, Line}, #state{owner = Owner} = State) ->
    Owner ! {transport_message, Line},
    {noreply, State};

handle_info({'EXIT', Pid, Reason}, #state{reader = Pid} = State) ->
    case Reason of
        normal ->
            {stop, normal, State};
        _ ->
            logger:error("Reader process died: ~p", [Reason]),
            {stop, {reader_died, Reason}, State}
    end;

handle_info({'EXIT', Pid, Reason}, #state{owner = Pid} = State) ->
    {stop, {owner_died, Reason}, State};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #state{reader = Reader}) when is_pid(Reader) ->
    exit(Reader, shutdown),
    ok;
terminate(_Reason, _State) ->
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec read_loop(pid(), pid()) -> no_return().
read_loop(Parent, Owner) ->
    case io:get_line("") of
        eof ->
            exit(normal);
        {error, Reason} ->
            logger:error("Read error: ~p", [Reason]),
            exit({read_error, Reason});
        Line when is_list(Line) ->
            BinaryLine = iolist_to_binary(Line),
            CleanLine = trim_line(BinaryLine),
            case byte_size(CleanLine) of
                0 ->
                    ok;  % Skip empty lines
                _ ->
                    Parent ! {line, CleanLine}
            end,
            read_loop(Parent, Owner);
        Line when is_binary(Line) ->
            CleanLine = trim_line(Line),
            case byte_size(CleanLine) of
                0 ->
                    ok;  % Skip empty lines
                _ ->
                    Parent ! {line, CleanLine}
            end,
            read_loop(Parent, Owner)
    end.

-spec trim_line(binary()) -> binary().
trim_line(Line) ->
    % Remove trailing newline and carriage return
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
        <<Content:(Size-2)/binary, "\r\n">> ->
            trim_end(Content);
        <<Content:(Size-1)/binary, "\n">> ->
            trim_end(Content);
        <<Content:(Size-1)/binary, "\r">> ->
            trim_end(Content);
        _ ->
            Binary
    end.