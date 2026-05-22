-module(test_calc_handler).

-behaviour(erlmcp_server_handler).

-export([tools/0, handle_tool/3]).

-spec tools() -> [map()].
tools() ->
    [#{
        name => <<"add">>,
        description => <<"Add two numbers">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"a">>, erlmcp_schema:number(), [required]),
            erlmcp_schema:field(<<"b">>, erlmcp_schema:number(), [required])
        ]),
        category => <<"math">>,
        when_to_use => <<"When you need to add two numbers">>
    }].

-spec handle_tool(binary(), map(), erlmcp_ctx:ctx()) ->
    {ok, term()} | {error, integer(), binary()}.
handle_tool(<<"add">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    Sum = A + B,
    {ok, erlmcp:text(list_to_binary(integer_to_list(trunc(Sum))))}.
