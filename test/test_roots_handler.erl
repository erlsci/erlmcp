-module(test_roots_handler).

-behaviour(erlmcp_roots).

-export([list_roots/1]).

-spec list_roots(erlmcp_ctx:ctx()) -> {ok, [map()]} | {error, term()}.
list_roots(_Ctx) ->
    {ok, [
        #{<<"uri">> => <<"file:///project">>, <<"name">> => <<"Project Root">>},
        #{<<"uri">> => <<"file:///home">>, <<"name">> => <<"Home">>}
    ]}.
