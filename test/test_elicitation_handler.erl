-module(test_elicitation_handler).

-behaviour(erlmcp_elicitation).

-export([handle_elicit/2]).

-spec handle_elicit(map(), erlmcp_ctx:ctx()) -> {ok, map()} | {error, term()}.
handle_elicit(Params, _Ctx) ->
    Message = maps:get(<<"message">>, Params, <<"Confirm?">>),
    {ok, #{<<"action">> => <<"accept">>,
           <<"content">> => #{<<"type">> => <<"text">>,
                              <<"text">> => <<"Accepted: ", Message/binary>>}}}.
