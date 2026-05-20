-module(erlmcp_client_advanced_tests).

-include_lib("eunit/include/eunit.hrl").

-include("erlmcp.hrl").

client_advanced_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [{"Batch request processing", fun test_batch_requests/0},
      {"Resource subscriptions", fun test_resource_subscriptions/0},
      {"Notification handlers", fun test_notification_handlers/0},
      {"Sampling handlers", fun test_sampling_handlers/0},
      {"Strict mode validation", fun test_strict_mode/0},
      {"Enhanced error handling", fun test_enhanced_error_handling/0},
      {"Resource templates", fun test_resource_templates/0}]}.

setup() ->
    TransportOpts = {stdio, []},
    Options = #{strict_mode => false},
    {ok, Client} = erlmcp_client:start_link(TransportOpts, Options),
    Client.

cleanup(Client) ->
    erlmcp_client:stop(Client).

test_batch_requests() ->
    ?debugMsg("Skipping batch requests test - requires MCP server"),
    ok.

test_resource_subscriptions() ->
    ?debugMsg("Skipping resource subscription test - requires MCP server"),
    ok.

test_notification_handlers() ->
    Client = setup(),
    try
        Handler = fun(Method, Params) -> io:format("Notification: ~p ~p~n", [Method, Params]) end,
        ok = erlmcp_client:set_notification_handler(Client, <<"test/notification">>, Handler),
        ok = erlmcp_client:remove_notification_handler(Client, <<"test/notification">>)
    after
        cleanup(Client)
    end.

test_sampling_handlers() ->
    Client = setup(),
    try
        Handler =
            fun(Method, Params) -> io:format("Sampling request: ~p ~p~n", [Method, Params]) end,
        ok = erlmcp_client:set_sampling_handler(Client, Handler),
        ok = erlmcp_client:remove_sampling_handler(Client)
    after
        cleanup(Client)
    end.

test_strict_mode() ->
    Client = setup(),
    try
        ok = erlmcp_client:set_strict_mode(Client, true),
        ok = erlmcp_client:set_strict_mode(Client, false)
    after
        cleanup(Client)
    end.

test_enhanced_error_handling() ->
    ?debugMsg("Skipping enhanced error handling test - requires MCP server"),
    ok.

test_resource_templates() ->
    ?debugMsg("Skipping resource templates test - requires MCP server"),
    ok.
