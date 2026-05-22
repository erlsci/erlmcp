-module(example_calculator_handler).

-behaviour(erlmcp_server_handler).

-export([tools/0, handle_tool/3]).

-spec tools() -> [map()].
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
          annotations => #{readOnlyHint => true}},

        #{name => <<"subtract">>,
          description => <<"Subtract b from a">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to subtract one number from another">>,
          returns => <<"The difference a - b">>,
          next => [<<"add">>, <<"multiply">>],
          annotations => #{readOnlyHint => true}},

        #{name => <<"multiply">>,
          description => <<"Multiply two numbers">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to multiply two numbers">>,
          returns => <<"The product of a and b">>,
          next => [<<"divide">>],
          annotations => #{readOnlyHint => true}},

        #{name => <<"divide">>,
          description => <<"Divide a by b">>,
          input_schema => erlmcp_schema:object([
              erlmcp_schema:field(<<"a">>, erlmcp_schema:number(), [required]),
              erlmcp_schema:field(<<"b">>, erlmcp_schema:number(),
                  [required, {doc, <<"Divisor (must not be zero)">>}])
          ]),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to divide one number by another">>,
          returns => <<"The quotient a / b">>,
          next => [<<"multiply">>],
          annotations => #{readOnlyHint => true}},

        #{name => <<"convert">>,
          description => <<"Convert between temperature units">>,
          entry_point => true,
          input_schema => erlmcp_schema:object([
              erlmcp_schema:field(<<"value">>, erlmcp_schema:number(), [required]),
              erlmcp_schema:field(<<"from">>, erlmcp_schema:enum([<<"c">>, <<"f">>]),
                  [required]),
              erlmcp_schema:field(<<"to">>, erlmcp_schema:enum([<<"c">>, <<"f">>]),
                  [required])
          ]),
          output_schema => OutSchema,
          category => <<"conversion">>,
          when_to_use => <<"When you need to convert between Celsius and Fahrenheit">>,
          returns => <<"The converted temperature value">>,
          next => [],
          annotations => #{readOnlyHint => true}}
    ].

-spec handle_tool(binary(), map(), erlmcp_ctx:ctx()) ->
    {ok, term()} | {ok, term(), map()} | {error, integer(), binary()}.
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
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"convert">>, #{<<"value">> := V, <<"from">> := <<"c">>, <<"to">> := <<"f">>}, _Ctx) ->
    R = V * 9 / 5 + 32,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"convert">>, #{<<"value">> := V, <<"from">> := <<"f">>, <<"to">> := <<"c">>}, _Ctx) ->
    R = (V - 32) * 5 / 9,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"convert">>, #{<<"value">> := V, <<"from">> := U, <<"to">> := U}, _Ctx) ->
    {ok, erlmcp:text(format_num(V)), #{<<"result">> => V}}.

%%====================================================================
%% Internal
%%====================================================================

two_number_schema() ->
    erlmcp_schema:object([
        erlmcp_schema:field(<<"a">>, erlmcp_schema:number(), [required]),
        erlmcp_schema:field(<<"b">>, erlmcp_schema:number(), [required])
    ]).

format_num(N) when is_integer(N) ->
    integer_to_binary(N);
format_num(N) when is_float(N) ->
    float_to_binary(N, [{decimals, 10}, compact]).
