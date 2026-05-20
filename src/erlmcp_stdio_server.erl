-module(erlmcp_stdio_server).

-behaviour(gen_server).

-include("erlmcp.hrl").

%% API exports
-export([start_link/1, add_tool/3, add_tool/4, add_resource/3, add_resource/4,
         add_prompt/3, add_prompt/4, stop/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

%% Types
-type tool_handler() :: fun((map()) -> binary() | iolist()).
-type resource_handler() :: fun((binary()) -> binary() | iolist()).
-type prompt_handler() :: fun((map()) -> binary() | iolist() | [map()]).

-record(state,
        {tools = #{} :: #{binary() => {binary(), tool_handler(), map() | undefined}},
         resources = #{} ::
             #{binary() =>
                   {binary(), resource_handler()} | {binary(), resource_handler(), binary()}},
         prompts = #{} :: #{binary() => {binary(), prompt_handler(), [map()] | undefined}},
         initialized = false :: boolean(),
         reader_pid :: pid() | undefined}).

-type state() :: #state{}.

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Options], []).

-spec add_tool(binary(), binary(), tool_handler()) -> ok | {error, term()}.
add_tool(Name, Description, Handler) ->
    add_tool(Name, Description, Handler, undefined).

-spec add_tool(binary(), binary(), tool_handler(), map() | undefined) ->
                  ok | {error, term()}.
add_tool(Name, Description, Handler, Schema)
    when is_binary(Name), is_binary(Description), is_function(Handler, 1) ->
    gen_server:call(?MODULE, {add_tool, Name, Description, Handler, Schema}).

-spec add_resource(binary(), binary(), resource_handler()) -> ok | {error, term()}.
add_resource(Uri, Description, Handler) ->
    add_resource(Uri, Description, Handler, <<"text/plain">>).

-spec add_resource(binary(), binary(), resource_handler(), binary()) ->
                      ok | {error, term()}.
add_resource(Uri, Description, Handler, MimeType)
    when is_binary(Uri), is_binary(Description), is_function(Handler, 1) ->
    gen_server:call(?MODULE, {add_resource, Uri, Description, Handler, MimeType}).

-spec add_prompt(binary(), binary(), prompt_handler()) -> ok | {error, term()}.
add_prompt(Name, Description, Handler) ->
    add_prompt(Name, Description, Handler, undefined).

-spec add_prompt(binary(), binary(), prompt_handler(), [map()] | undefined) ->
                    ok | {error, term()}.
add_prompt(Name, Description, Handler, Arguments)
    when is_binary(Name), is_binary(Description), is_function(Handler, 1) ->
    gen_server:call(?MODULE, {add_prompt, Name, Description, Handler, Arguments}).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init([map()]) -> {ok, state()} | {stop, term()}.
init([_Options]) ->
    process_flag(trap_exit, true),

    logger:info("Initializing erlmcp_stdio_server"),

    % Ensure jsx is available
    case catch application:ensure_all_started(jsx) of
        {'EXIT', Reason} ->
            logger:error("Failed to start jsx application: ~p", [Reason]),
            {stop, {jsx_start_error, Reason}};
        {error, Reason} ->
            logger:error("Failed to start jsx application: ~p", [Reason]),
            {stop, {jsx_start_error, Reason}};
        _ ->
            logger:info("jsx started successfully"),
            % Start the stdin reader process
            logger:info("Starting stdin reader process"),
            ServerPid = self(),
            ReaderPid = spawn_link(fun() -> stdin_reader_loop(ServerPid) end),
            logger:info("Stdin reader process started: ~p", [ReaderPid]),
            {ok, #state{reader_pid = ReaderPid}}
    end.

-spec handle_call(term(), {pid(), term()}, state()) -> {reply, term(), state()}.
handle_call({add_tool, Name, Description, Handler, Schema}, _From, State) ->
    NewTools = maps:put(Name, {Description, Handler, Schema}, State#state.tools),
    {reply, ok, State#state{tools = NewTools}};
handle_call({add_resource, Uri, Description, Handler, MimeType}, _From, State) ->
    NewResources = maps:put(Uri, {Description, Handler, MimeType}, State#state.resources),
    {reply, ok, State#state{resources = NewResources}};
handle_call({add_prompt, Name, Description, Handler, Arguments}, _From, State) ->
    NewPrompts = maps:put(Name, {Description, Handler, Arguments}, State#state.prompts),
    {reply, ok, State#state{prompts = NewPrompts}};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info({stdin_line, Line}, State) ->
    logger:info("Received stdin line: ~s", [Line]),
    NewState = handle_json_rpc_message(Line, State),
    {noreply, NewState};
handle_info({'EXIT', Pid, Reason}, #state{reader_pid = Pid} = State) ->
    logger:info("Stdin reader process ~p exited with reason: ~p", [Pid, Reason]),
    case Reason of
        normal ->
            logger:info("Stdin reader finished normally"),
            {stop, normal, State};
        _ ->
            logger:error("Stdin reader died: ~p", [Reason]),
            {stop, {reader_died, Reason}, State}
    end;
handle_info(Info, State) ->
    logger:warning("Unexpected info message: ~p", [Info]),
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #state{reader_pid = ReaderPid}) when is_pid(ReaderPid) ->
    logger:info("Terminating, killing reader process ~p", [ReaderPid]),
    exit(ReaderPid, shutdown),
    ok;
terminate(_Reason, _State) ->
    logger:info("Terminating (no reader process)"),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions - Stdin Reader
%%====================================================================

-spec stdin_reader_loop(pid()) -> no_return().
stdin_reader_loop(Parent) ->
    logger:info("Stdin reader starting, parent: ~p", [Parent]),

    case read_stdin_line() of
        {ok, Line} ->
            CleanLine = string:trim(Line),
            case CleanLine of
                "" ->
                    stdin_reader_loop(Parent);
                _ ->
                    logger:info("Stdin reader got line: ~s", [CleanLine]),
                    Parent ! {stdin_line, CleanLine},
                    stdin_reader_loop(Parent)
            end;
        eof ->
            logger:info("EOF received from stdin, stopping reader"),
            exit(normal);
        {error, Reason} ->
            logger:error("Stdin read error: ~p", [Reason]),
            exit({read_error, Reason})
    end.

-spec read_stdin_line() -> {ok, string()} | eof | {error, term()}.
read_stdin_line() ->
    try
        % Try the standard approach first
        case io:get_line("") of
            eof ->
                eof;
            {error, ReadReason} ->
                {error, ReadReason};
            Line when is_list(Line) ->
                {ok, Line};
            Line when is_binary(Line) ->
                {ok, binary_to_list(Line)};
            Other ->
                logger:warning("Unexpected io:get_line result: ~p", [Other]),
                {error, {unexpected_result, Other}}
        end
    catch
        error:enotsup ->
            % stdin might not be available in this environment
            logger:error("io:get_line not supported in this environment"),
            {error, enotsup};
        Error:ExceptionReason:Stack ->
            logger:error("Exception in read_stdin_line: ~p:~p~n~p",
                         [Error, ExceptionReason, Stack]),
            {error, {exception, Error, ExceptionReason}}
    end.

%%====================================================================
%% Internal Functions - JSON-RPC Message Handling
%%====================================================================

-spec handle_json_rpc_message(string(), state()) -> state().
handle_json_rpc_message(Message, State) ->
    logger:info("Parsing JSON-RPC message: ~s", [Message]),
    try jsx:decode(list_to_binary(Message), [return_maps]) of
        #{<<"method">> := <<"initialize">>, <<"id">> := Id} = Request ->
            logger:info("Handling initialize request with ID: ~p", [Id]),
            handle_initialize(Id, Request, State);
        #{<<"method">> := <<"notifications/initialized">>} ->
            logger:info("Received initialized notification"),
            State;
        #{<<"method">> := Method, <<"id">> := Id} = Request ->
            logger:info("Handling method call: ~s with ID: ~p", [Method, Id]),
            handle_method_call(Method, Id, Request, State);
        Other ->
            logger:warning("Unknown message format: ~p", [Other]),
            State
    catch
        Error:Reason:Stack ->
            logger:error("JSON parse error: ~p:~p~n~p", [Error, Reason, Stack]),
            State
    end.

-spec handle_initialize(term(), map(), state()) -> state().
handle_initialize(Id, _Request, State) ->
    logger:info("Building initialize response for ID: ~p", [Id]),
    Response =
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"id">> => Id,
          <<"result">> =>
              #{<<"protocolVersion">> => ?MCP_VERSION,
                <<"capabilities">> =>
                    #{<<"tools">> => #{<<"listChanged">> => false},
                      <<"resources">> => #{<<"subscribe">> => false, <<"listChanged">> => false},
                      <<"prompts">> => #{<<"listChanged">> => false}},
                <<"serverInfo">> =>
                    #{<<"name">> => <<"erlmcp-stdio">>, <<"version">> => <<"1.0.0">>}}},
    logger:info("Sending initialize response: ~p", [Response]),
    send_response(Response),
    logger:info("Initialize response sent, marking as initialized"),
    State#state{initialized = true}.

-spec handle_method_call(binary(), term(), map(), state()) -> state().
handle_method_call(<<"tools/list">>, Id, _Request, State) ->
    logger:info("Handling tools/list request"),
    Tools = build_tools_list(State),
    Response =
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"id">> => Id,
          <<"result">> => #{<<"tools">> => Tools}},
    send_response(Response),
    State;
handle_method_call(<<"tools/call">>, Id, #{<<"params">> := Params}, State) ->
    logger:info("Handling tools/call request with params: ~p", [Params]),
    handle_tool_call(Id, Params, State),
    State;
handle_method_call(<<"resources/list">>, Id, _Request, State) ->
    logger:info("Handling resources/list request"),
    Resources = build_resources_list(State),
    Response =
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"id">> => Id,
          <<"result">> => #{<<"resources">> => Resources}},
    send_response(Response),
    State;
handle_method_call(<<"resources/read">>, Id, #{<<"params">> := Params}, State) ->
    logger:info("Handling resources/read request with params: ~p", [Params]),
    handle_resource_read(Id, Params, State),
    State;
handle_method_call(<<"prompts/list">>, Id, _Request, State) ->
    logger:info("Handling prompts/list request"),
    Prompts = build_prompts_list(State),
    Response =
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"id">> => Id,
          <<"result">> => #{<<"prompts">> => Prompts}},
    send_response(Response),
    State;
handle_method_call(<<"prompts/get">>, Id, #{<<"params">> := Params}, State) ->
    logger:info("Handling prompts/get request with params: ~p", [Params]),
    handle_prompt_get(Id, Params, State),
    State;
handle_method_call(Method, Id, _Request, State) ->
    logger:warning("Unknown method: ~s", [Method]),
    Error =
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"id">> => Id,
          <<"error">> =>
              #{<<"code">> => -32601, <<"message">> => <<"Method not found: ", Method/binary>>}},
    send_response(Error),
    State.

%%====================================================================
%% Internal Functions - Response Building
%%====================================================================

-spec build_tools_list(state()) -> [map()].
build_tools_list(State) ->
    maps:fold(fun(Name, {Description, _Handler, Schema}, Acc) ->
                 Tool = #{<<"name">> => Name, <<"description">> => Description},
                 ToolWithSchema =
                     case Schema of
                         undefined ->
                             Tool;
                         _ ->
                             Tool#{<<"inputSchema">> => Schema}
                     end,
                 [ToolWithSchema | Acc]
              end,
              [],
              State#state.tools).

-spec build_resources_list(state()) -> [map()].
build_resources_list(State) ->
    maps:fold(fun (Uri, {Description, _Handler}, Acc) ->
                      Resource =
                          #{<<"uri">> => Uri,
                            <<"name">> => Description,
                            <<"mimeType">> => <<"text/plain">>},
                      [Resource | Acc];
                  (Uri, {Description, _Handler, MimeType}, Acc) ->
                      Resource =
                          #{<<"uri">> => Uri,
                            <<"name">> => Description,
                            <<"mimeType">> => MimeType},
                      [Resource | Acc]
              end,
              [],
              State#state.resources).

-spec build_prompts_list(state()) -> [map()].
build_prompts_list(State) ->
    maps:fold(fun(Name, {Description, _Handler, Arguments}, Acc) ->
                 Prompt = #{<<"name">> => Name, <<"description">> => Description},
                 PromptWithArgs =
                     case Arguments of
                         undefined ->
                             Prompt;
                         _ ->
                             Prompt#{<<"arguments">> => Arguments}
                     end,
                 [PromptWithArgs | Acc]
              end,
              [],
              State#state.prompts).

%%====================================================================
%% Internal Functions - Handler Execution
%%====================================================================

-spec handle_tool_call(term(), map(), state()) -> ok.
handle_tool_call(Id, #{<<"name">> := Name, <<"arguments">> := Arguments}, State) ->
    logger:info("Executing tool: ~s with arguments: ~p", [Name, Arguments]),
    case maps:get(Name, State#state.tools, undefined) of
        undefined ->
            logger:warning("Tool not found: ~s", [Name]),
            Error =
                #{<<"jsonrpc">> => <<"2.0">>,
                  <<"id">> => Id,
                  <<"error">> => #{<<"code">> => -32601, <<"message">> => <<"Tool not found">>}},
            send_response(Error);
        {_Description, Handler, _Schema} ->
            try
                Result = Handler(Arguments),
                ResultBinary = to_binary(Result),
                logger:info("Tool execution result: ~s", [ResultBinary]),
                Response =
                    #{<<"jsonrpc">> => <<"2.0">>,
                      <<"id">> => Id,
                      <<"result">> =>
                          #{<<"content">> =>
                                [#{<<"type">> => <<"text">>, <<"text">> => ResultBinary}]}},
                send_response(Response)
            catch
                Class:Reason:Stack ->
                    logger:error("Tool handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
                    Error =
                        #{<<"jsonrpc">> => <<"2.0">>,
                          <<"id">> => Id,
                          <<"error">> =>
                              #{<<"code">> => -32603, <<"message">> => <<"Internal error">>}},
                    send_response(Error)
            end
    end;
handle_tool_call(Id, Params, _State) ->
    logger:warning("Invalid tool call parameters: ~p", [Params]),
    Error =
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"id">> => Id,
          <<"error">> => #{<<"code">> => -32602, <<"message">> => <<"Invalid parameters">>}},
    send_response(Error).

-spec handle_resource_read(term(), map(), state()) -> ok.
handle_resource_read(Id, #{<<"uri">> := Uri}, State) ->
    logger:info("Reading resource: ~s", [Uri]),
    case maps:get(Uri, State#state.resources, undefined) of
        undefined ->
            logger:warning("Resource not found: ~s", [Uri]),
            Error =
                #{<<"jsonrpc">> => <<"2.0">>,
                  <<"id">> => Id,
                  <<"error">> =>
                      #{<<"code">> => -32602, <<"message">> => <<"Resource not found">>}},
            send_response(Error);
        {_Description, Handler} ->
            handle_resource_with_handler(Id, Uri, Handler, <<"text/plain">>);
        {_Description, Handler, MimeType} ->
            handle_resource_with_handler(Id, Uri, Handler, MimeType)
    end;
handle_resource_read(Id, Params, _State) ->
    logger:warning("Invalid resource read parameters: ~p", [Params]),
    Error =
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"id">> => Id,
          <<"error">> => #{<<"code">> => -32602, <<"message">> => <<"Invalid parameters">>}},
    send_response(Error).

-spec handle_resource_with_handler(term(), binary(), fun(), binary()) -> ok.
handle_resource_with_handler(Id, Uri, Handler, MimeType) ->
    try
        Content = Handler(Uri),
        ContentBinary = to_binary(Content),
        logger:info("Resource content generated for ~s: ~s", [Uri, ContentBinary]),
        Response =
            #{<<"jsonrpc">> => <<"2.0">>,
              <<"id">> => Id,
              <<"result">> =>
                  #{<<"contents">> =>
                        [#{<<"uri">> => Uri,
                           <<"mimeType">> => MimeType,
                           <<"text">> => ContentBinary}]}},
        send_response(Response)
    catch
        Class:Reason:Stack ->
            logger:error("Resource handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
            Error =
                #{<<"jsonrpc">> => <<"2.0">>,
                  <<"id">> => Id,
                  <<"error">> => #{<<"code">> => -32603, <<"message">> => <<"Internal error">>}},
            send_response(Error)
    end.

-spec handle_prompt_get(term(), map(), state()) -> ok.
handle_prompt_get(Id, #{<<"name">> := Name} = Params, State) ->
    logger:info("Getting prompt: ~s", [Name]),
    case maps:get(Name, State#state.prompts, undefined) of
        undefined ->
            logger:warning("Prompt not found: ~s", [Name]),
            Error =
                #{<<"jsonrpc">> => <<"2.0">>,
                  <<"id">> => Id,
                  <<"error">> => #{<<"code">> => -32602, <<"message">> => <<"Prompt not found">>}},
            send_response(Error);
        {_Description, Handler, _Arguments} ->
            try
                Arguments = maps:get(<<"arguments">>, Params, #{}),
                Result = Handler(Arguments),
                Messages = normalize_prompt_result(Result),
                logger:info("Prompt result generated for ~s", [Name]),
                Response =
                    #{<<"jsonrpc">> => <<"2.0">>,
                      <<"id">> => Id,
                      <<"result">> => #{<<"messages">> => Messages}},
                send_response(Response)
            catch
                Class:Reason:Stack ->
                    logger:error("Prompt handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
                    Error =
                        #{<<"jsonrpc">> => <<"2.0">>,
                          <<"id">> => Id,
                          <<"error">> =>
                              #{<<"code">> => -32603, <<"message">> => <<"Internal error">>}},
                    send_response(Error)
            end
    end;
handle_prompt_get(Id, Params, _State) ->
    logger:warning("Invalid prompt get parameters: ~p", [Params]),
    Error =
        #{<<"jsonrpc">> => <<"2.0">>,
          <<"id">> => Id,
          <<"error">> => #{<<"code">> => -32602, <<"message">> => <<"Invalid parameters">>}},
    send_response(Error).

%%====================================================================
%% Internal Functions - Utilities
%%====================================================================

-spec send_response(map()) -> ok.
send_response(Response) ->
    Json = jsx:encode(Response),
    logger:info("Sending JSON response: ~s", [Json]),
    io:format("~s~n", [Json]),
    logger:info("Response sent to stdout"),
    ok.

-spec to_binary(term()) -> binary().
to_binary(B) when is_binary(B) ->
    B;
to_binary(L) when is_list(L) ->
    iolist_to_binary(L);
to_binary(A) when is_atom(A) ->
    atom_to_binary(A, utf8);
to_binary(I) when is_integer(I) ->
    integer_to_binary(I);
to_binary(F) when is_float(F) ->
    float_to_binary(F, [{decimals, 2}]);
to_binary(Other) ->
    iolist_to_binary(io_lib:format("~p", [Other])).

-spec normalize_prompt_result(term()) -> [map()].
normalize_prompt_result(Result) when is_binary(Result) ->
    [#{<<"role">> => <<"user">>,
       <<"content">> => #{<<"type">> => <<"text">>, <<"text">> => Result}}];
normalize_prompt_result(Result) when is_list(Result) ->
    case Result of
        [#{} | _] ->
            Result;  % Already a list of message maps
        _ ->
            normalize_prompt_result(iolist_to_binary(Result))
    end;
normalize_prompt_result(Result) ->
    normalize_prompt_result(to_binary(Result)).
