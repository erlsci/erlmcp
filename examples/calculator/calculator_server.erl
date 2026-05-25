-module(calculator_server).

%% A runnable calculator MCP server demonstrating:
%%   - Tool registration via the erlmcp_server_handler behaviour
%%   - Discoverability (instructions + the directory tool)
%%   - Task support (long-running tool with progress + cancel)
%%   - Icons on tools
%%   - _meta passthrough
%%   - Structured output (outputSchema)

-behaviour(erlmcp_server_handler).

-export([start/0, start/1, stop/1, slow_tool_spec/0]).
-export([tools/0, handle_tool/3]).

-spec start() -> {ok, #{server := pid(), transport := pid()}}.
start() ->
    start(#{}).

-spec start(map()) -> {ok, #{server := pid(), transport := pid()}}.
start(Config) ->
    {ok, #{server := Server} = Result} =
        erlmcp:start_stdio_setup(calculator, Config),
    ok = erlmcp:register_handler(Server, ?MODULE),
    ok = erlmcp:add_tool(Server, erlmcp:make_directory_tool()),
    ok = erlmcp:add_tool(Server, slow_tool_spec()),
    {ok, Result}.

-spec stop(pid()) -> ok.
stop(Server) ->
    gen_statem:stop(Server).

%%====================================================================
%% erlmcp_server_handler callbacks
%%====================================================================

tools() ->
    OutSchema = erlmcp_schema:object([
        erlmcp_schema:field(<<"result">>, erlmcp_schema:number(), [required])
    ]),
    [
        #{name => <<"add">>,
          description => <<"Add two numbers">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to add two numbers">>,
          returns => <<"The sum of a and b">>,
          next => [<<"subtract">>, <<"multiply">>],
          entry_point => true,
          icons => [#{<<"type">> => <<"emoji">>, <<"emoji">> => <<"➕">>}],
          annotations => #{readOnlyHint => true}},
        #{name => <<"subtract">>,
          description => <<"Subtract b from a">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to subtract">>,
          returns => <<"The difference a - b">>,
          next => [<<"add">>],
          annotations => #{readOnlyHint => true}},
        #{name => <<"multiply">>,
          description => <<"Multiply two numbers">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to multiply">>,
          returns => <<"The product of a and b">>,
          next => [<<"divide">>],
          annotations => #{readOnlyHint => true}},
        #{name => <<"divide">>,
          description => <<"Divide a by b">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to divide">>,
          returns => <<"The quotient a / b">>,
          next => [<<"multiply">>],
          annotations => #{readOnlyHint => true}}
    ].

handle_tool(<<"add">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    R = A + B,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"subtract">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    R = A - B,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"multiply">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    R = A * B,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"divide">>, #{<<"a">> := _A, <<"b">> := B}, _Ctx) when B == 0 ->
    {error, -32602, <<"Division by zero">>};
handle_tool(<<"divide">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    R = A / B,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}}.

%%====================================================================
%% Task-enabled slow tool (demonstrates task + progress + cancel)
%%====================================================================

slow_tool_spec() ->
    #{name => <<"slow_compute">>,
      description => <<"A long-running computation (demonstrates tasks)">>,
      input_schema => erlmcp_schema:object([
          erlmcp_schema:field(<<"steps">>, erlmcp_schema:integer([{min, 1}, {max, 100}]),
              [required])
      ]),
      category => <<"demo">>,
      task_support => allowed,
      handler => fun slow_compute/2}.

slow_compute(#{<<"steps">> := Steps}, Ctx) ->
    lists:foreach(fun(I) ->
        timer:sleep(50),
        erlmcp_ctx:report_progress(Ctx, I / Steps,
            <<"Step ", (integer_to_binary(I))/binary, "/",
              (integer_to_binary(Steps))/binary>>)
    end, lists:seq(1, Steps)),
    {ok, erlmcp:text(<<"Completed ", (integer_to_binary(Steps))/binary, " steps">>)}.

%%====================================================================
%% Internal
%%====================================================================

two_number_schema() ->
    erlmcp_schema:object([
        erlmcp_schema:field(<<"a">>, erlmcp_schema:number(), [required]),
        erlmcp_schema:field(<<"b">>, erlmcp_schema:number(), [required])
    ]).

format_num(N) when is_integer(N) -> integer_to_binary(N);
format_num(N) when is_float(N) -> float_to_binary(N, [{decimals, 10}, compact]).
