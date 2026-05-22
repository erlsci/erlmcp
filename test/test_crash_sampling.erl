-module(test_crash_sampling).

-behaviour(erlmcp_sampling).

-export([handle_create_message/2]).

handle_create_message(_Params, _Ctx) ->
    error(intentional_crash).
