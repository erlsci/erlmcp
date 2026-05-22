-module(test_sampling_handler).

-behaviour(erlmcp_sampling).

-export([handle_create_message/2]).

-spec handle_create_message(map(), erlmcp_ctx:ctx()) -> {ok, map()} | {error, term()}.
handle_create_message(Params, _Ctx) ->
    Messages = maps:get(<<"messages">>, Params, []),
    {ok, #{<<"role">> => <<"assistant">>,
           <<"model">> => <<"test-model">>,
           <<"content">> => #{<<"type">> => <<"text">>,
                              <<"text">> => <<"Echo: ",
                                  (integer_to_binary(length(Messages)))/binary,
                                  " messages">>}}}.
