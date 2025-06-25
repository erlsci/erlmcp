-module(calculator_client).
-behaviour(gen_statem).

-include("erlmcp.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    connect/2,
    calculate/2,
    get_history/1,
    clear_history/1,
    stop/1
]).

%% gen_statem callbacks
-export([
    init/1,
    callback_mode/0,
    terminate/3,
    code_change/4
]).

%% State callbacks
-export([
    disconnected/3,
    connecting/3,
    connected/3,
    ready/3
]).

-define(SERVER, ?MODULE).
-define(RECONNECT_DELAY, 5000).

%% State data
-record(data, {
    mcp_client :: pid() | undefined,
    server_info :: map() | undefined,
    capabilities :: #mcp_server_capabilities{} | undefined,
    history = [] :: [calculation()],
    pending_requests = queue:new() :: queue:queue(),
    reconnect_timer :: reference() | undefined,
    connection_opts :: map()
}).

-type calculation() :: #{
    expression := binary(),
    result := term(),
    timestamp := erlang:timestamp()
}.

%%====================================================================
%% API
%%====================================================================

start_link() ->
    start_link(#{}).

start_link(Options) ->
    gen_statem:start_link(?MODULE, Options, []).

connect(Client, ServerAddress) ->
    gen_statem:call(Client, {connect, ServerAddress}).

calculate(Client, Expression) ->
    gen_statem:call(Client, {calculate, Expression}, 10000).

get_history(Client) ->
    gen_statem:call(Client, get_history).

clear_history(Client) ->
    gen_statem:call(Client, clear_history).

stop(Client) ->
    gen_statem:stop(Client).

%%====================================================================
%% gen_statem callbacks
%%====================================================================

init(Options) ->
    process_flag(trap_exit, true),
    Data = #data{
        connection_opts = Options
    },
    {ok, disconnected, Data}.

callback_mode() ->
    [state_functions, state_enter].

%%====================================================================
%% State: disconnected
%%====================================================================

disconnected(enter, _OldState, Data) ->
    logger:info("Calculator client disconnected"),
    %% Cancel any existing reconnect timer
    cancel_reconnect_timer(Data),
    {keep_state_and_data, []};

disconnected({call, From}, {connect, ServerAddress}, Data) ->
    logger:info("Connecting to calculator server at ~p", [ServerAddress]),
    {next_state, connecting, Data#data{connection_opts = ServerAddress},
     [{reply, From, ok}]};

disconnected({call, From}, {calculate, _}, _Data) ->
    {keep_state_and_data, [{reply, From, {error, not_connected}}]};

disconnected({call, From}, get_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.history}}]};

disconnected({call, From}, clear_history, Data) ->
    {next_state, disconnected, Data#data{history = []},
     [{reply, From, ok}]}.

%%====================================================================
%% State: connecting
%%====================================================================

connecting(enter, _OldState, Data) ->
    %% Start MCP client
    TransportOpts = build_transport_opts(Data#data.connection_opts),
    ClientOpts = #{
        strict_mode => false,
        timeout => 5000
    },
    
    case erlmcp_client:start_link(TransportOpts, ClientOpts) of
        {ok, McpClient} ->
            %% Set up handlers
            setup_handlers(McpClient),
            
            %% Initialize connection
            Capabilities = #mcp_client_capabilities{
                roots = #mcp_capability{enabled = true},
                sampling = #mcp_capability{enabled = false}
            },
            
            case erlmcp_client:initialize(McpClient, Capabilities) of
                {ok, InitResult} ->
                    ServerInfo = maps:get(<<"serverInfo">>, InitResult, #{}),
                    Capabilities = extract_capabilities(InitResult),
                    logger:info("Connected to server: ~p", [ServerInfo]),
                    
                    NewData = Data#data{
                        mcp_client = McpClient,
                        server_info = ServerInfo,
                        capabilities = Capabilities
                    },
                    {next_state, connected, NewData};
                {error, Reason} ->
                    logger:error("Failed to initialize MCP connection: ~p", [Reason]),
                    erlmcp_client:stop(McpClient),
                    schedule_reconnect(Data)
            end;
        {error, Reason} ->
            logger:error("Failed to start MCP client: ~p", [Reason]),
            schedule_reconnect(Data)
    end;

connecting({call, From}, {calculate, Expression}, Data) ->
    %% Queue the request
    NewQueue = queue:in({calculate, Expression, From}, Data#data.pending_requests),
    {keep_state, Data#data{pending_requests = NewQueue}, []};

connecting({call, From}, _, _Data) ->
    {keep_state_and_data, [{reply, From, {error, connecting}}]}.

%%====================================================================
%% State: connected
%%====================================================================

connected(enter, _OldState, Data) ->
    %% Verify server capabilities
    case verify_calculator_capabilities(Data#data.mcp_client) of
        ok ->
            %% Process any pending requests
            process_pending_requests(Data),
            {next_state, ready, Data};
        {error, Reason} ->
            logger:error("Server doesn't support calculator capabilities: ~p", [Reason]),
            disconnect_and_retry(Data)
    end;

connected({call, From}, _, _Data) ->
    {keep_state_and_data, [{reply, From, {error, initializing}}]}.

%%====================================================================
%% State: ready
%%====================================================================

ready(enter, _OldState, _Data) ->
    logger:info("Calculator client ready"),
    keep_state_and_data;

ready({call, From}, {calculate, Expression}, Data) ->
    case perform_calculation(Expression, Data) of
        {ok, Result} ->
            %% Store in history
            Calculation = #{
                expression => Expression,
                result => Result,
                timestamp => erlang:timestamp()
            },
            NewHistory = [Calculation | Data#data.history],
            NewData = Data#data{history = NewHistory},
            
            {keep_state, NewData, [{reply, From, {ok, Result}}]};
        {error, Reason} = Error ->
            logger:error("Calculation failed: ~p", [Reason]),
            {keep_state_and_data, [{reply, From, Error}]}
    end;

ready({call, From}, get_history, Data) ->
    {keep_state_and_data, [{reply, From, {ok, Data#data.history}}]};

ready({call, From}, clear_history, Data) ->
    {keep_state, Data#data{history = []}, [{reply, From, ok}]};

ready(info, {'EXIT', Pid, Reason}, #data{mcp_client = Pid} = Data) ->
    logger:error("MCP client died: ~p", [Reason]),
    schedule_reconnect(Data#data{mcp_client = undefined});

ready(info, {resource_updated, Uri, Metadata}, Data) ->
    logger:info("Resource updated: ~s, metadata: ~p", [Uri, Metadata]),
    {keep_state, Data}.

%%====================================================================
%% Common state callbacks
%%====================================================================

terminate(_Reason, _State, #data{mcp_client = McpClient}) when is_pid(McpClient) ->
    erlmcp_client:stop(McpClient),
    ok;
terminate(_Reason, _State, _Data) ->
    ok.

code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.

%%====================================================================
%% Internal functions - Connection Management
%%====================================================================

build_transport_opts(#{type := tcp, host := Host, port := Port}) ->
    {tcp, #{host => Host, port => Port}};
build_transport_opts(#{type := http, url := Url}) ->
    {http, #{url => Url}};
build_transport_opts(_) ->
    {stdio, []}.

setup_handlers(McpClient) ->
    %% Set up notification handlers
    erlmcp_client:set_notification_handler(
        McpClient,
        <<"resources/updated">>,
        fun(Method, Params) ->
            self() ! {notification, Method, Params}
        end
    ),
    
    erlmcp_client:set_notification_handler(
        McpClient,
        <<"tools/updated">>,
        fun(Method, Params) ->
            logger:info("Tools updated: ~p", [Params])
        end
    ),
    ok.

extract_capabilities(InitResult) ->
    case maps:get(<<"capabilities">>, InitResult, #{}) of
        Caps when is_map(Caps) ->
            #mcp_server_capabilities{
                tools = case maps:is_key(<<"tools">>, Caps) of
                    true -> #mcp_capability{enabled = true};
                    false -> undefined
                end,
                prompts = case maps:is_key(<<"prompts">>, Caps) of
                    true -> #mcp_capability{enabled = true};
                    false -> undefined
                end,
                resources = case maps:is_key(<<"resources">>, Caps) of
                    true -> #mcp_capability{enabled = true};
                    false -> undefined
                end
            };
        _ ->
            undefined
    end.

verify_calculator_capabilities(McpClient) ->
    %% Check if calculator tools are available
    case erlmcp_client:list_tools(McpClient) of
        {ok, #{<<"tools">> := Tools}} ->
            RequiredTools = [<<"calculate">>, <<"evaluate">>, <<"solve">>],
            AvailableTools = [maps:get(<<"name">>, Tool, <<>>) || Tool <- Tools],
            
            case lists:any(fun(Tool) -> lists:member(Tool, AvailableTools) end, RequiredTools) of
                true -> ok;
                false -> {error, no_calculator_tools}
            end;
        {error, Reason} ->
            {error, {list_tools_failed, Reason}}
    end.

schedule_reconnect(Data) ->
    Timer = erlang:send_after(?RECONNECT_DELAY, self(), reconnect),
    {next_state, disconnected, Data#data{reconnect_timer = Timer}}.

cancel_reconnect_timer(#data{reconnect_timer = undefined}) ->
    ok;
cancel_reconnect_timer(#data{reconnect_timer = Timer}) ->
    erlang:cancel_timer(Timer),
    ok.

disconnect_and_retry(#data{mcp_client = McpClient} = Data) when is_pid(McpClient) ->
    erlmcp_client:stop(McpClient),
    schedule_reconnect(Data#data{mcp_client = undefined});
disconnect_and_retry(Data) ->
    schedule_reconnect(Data).

process_pending_requests(#data{pending_requests = Queue} = Data) ->
    case queue:is_empty(Queue) of
        true -> ok;
        false ->
            lists:foreach(fun({calculate, Expression, From}) ->
                gen_statem:reply(From, {error, reconnected_try_again})
            end, queue:to_list(Queue))
    end.

%%====================================================================
%% Internal functions - Calculation
%%====================================================================

perform_calculation(Expression, #data{mcp_client = McpClient}) ->
    %% Try different calculation methods based on available tools
    case try_calculation_tool(McpClient, Expression) of
        {ok, _} = Result ->
            Result;
        {error, tool_not_found} ->
            %% Fallback to prompt if tools aren't available
            try_calculation_prompt(McpClient, Expression);
        Error ->
            Error
    end.

try_calculation_tool(McpClient, Expression) ->
    %% First, try the 'calculate' tool
    case erlmcp_client:call_tool(McpClient, <<"calculate">>, 
                                  #{<<"expression">> => Expression}) of
        {ok, #{<<"content">> := [Content | _]}} ->
            parse_calculation_result(Content);
        {error, {error_response, #{<<"code">> := -32602}}} ->
            %% Tool not found, try 'evaluate' tool
            case erlmcp_client:call_tool(McpClient, <<"evaluate">>, 
                                          #{<<"expression">> => Expression}) of
                {ok, #{<<"content">> := [Content | _]}} ->
                    parse_calculation_result(Content);
                _ ->
                    {error, tool_not_found}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

try_calculation_prompt(McpClient, Expression) ->
    %% Use a calculation prompt as fallback
    case erlmcp_client:get_prompt(McpClient, <<"calculate">>, 
                                  #{<<"expression">> => Expression}) of
        {ok, #{<<"messages">> := Messages}} ->
            extract_result_from_messages(Messages);
        {error, {error_response, #{<<"code">> := -32602}}} ->
            %% No calculation prompt, try a general math prompt
            try_general_calculation(McpClient, Expression);
        {error, Reason} ->
            {error, Reason}
    end.

try_general_calculation(McpClient, Expression) ->
    %% Last resort: try to find any math-related tool or prompt
    case erlmcp_client:list_tools(McpClient) of
        {ok, #{<<"tools">> := Tools}} ->
            MathTools = find_math_tools(Tools),
            try_math_tools(McpClient, Expression, MathTools);
        _ ->
            {error, no_calculation_capability}
    end.

find_math_tools(Tools) ->
    MathKeywords = [<<"math">>, <<"calc">>, <<"compute">>, <<"eval">>],
    lists:filter(fun(Tool) ->
        Name = maps:get(<<"name">>, Tool, <<>>),
        Desc = maps:get(<<"description">>, Tool, <<>>),
        lists:any(fun(Keyword) ->
            binary:match(Name, Keyword) =/= nomatch orelse
            binary:match(Desc, Keyword) =/= nomatch
        end, MathKeywords)
    end, Tools).

try_math_tools(_McpClient, _Expression, []) ->
    {error, no_math_tools};
try_math_tools(McpClient, Expression, [Tool | Rest]) ->
    ToolName = maps:get(<<"name">>, Tool),
    case erlmcp_client:call_tool(McpClient, ToolName, 
                                  #{<<"input">> => Expression}) of
        {ok, #{<<"content">> := [Content | _]}} ->
            parse_calculation_result(Content);
        _ ->
            try_math_tools(McpClient, Expression, Rest)
    end.

parse_calculation_result(#{<<"type">> := <<"text">>, <<"text">> := Text}) ->
    %% Try to extract numeric result from text
    case parse_numeric_result(Text) of
        {ok, Number} -> {ok, Number};
        error -> {ok, Text}  % Return text if we can't parse a number
    end;
parse_calculation_result(#{<<"data">> := Data}) ->
    {ok, Data};
parse_calculation_result(_) ->
    {error, invalid_result_format}.

parse_numeric_result(Text) ->
    %% Simple numeric parser - in real implementation would be more robust
    TextStr = binary_to_list(Text),
    case string:tokens(TextStr, "=") of
        [_, Result] ->
            case string:to_float(string:strip(Result)) of
                {Float, []} -> {ok, Float};
                _ ->
                    case string:to_integer(string:strip(Result)) of
                        {Int, []} -> {ok, Int};
                        _ -> error
                    end
            end;
        _ ->
            %% Try to parse as a single number
            case string:to_float(TextStr) of
                {Float, []} -> {ok, Float};
                _ ->
                    case string:to_integer(TextStr) of
                        {Int, []} -> {ok, Int};
                        _ -> error
                    end
            end
    end.

extract_result_from_messages([#{<<"content">> := Content} | _]) when is_binary(Content) ->
    parse_numeric_result(Content);
extract_result_from_messages([#{<<"content">> := #{<<"text">> := Text}} | _]) ->
    parse_numeric_result(Text);
extract_result_from_messages([_ | Rest]) ->
    extract_result_from_messages(Rest);
extract_result_from_messages([]) ->
    {error, no_result_in_messages}.