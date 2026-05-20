-module(erlmcp_advanced_tests).

-include_lib("eunit/include/eunit.hrl").

-include("erlmcp.hrl").

advanced_server_test_() ->
    {setup,
     fun setup_advanced/0,
     fun cleanup/1,
     fun(Server) ->
        [?_test(test_resource_template(Server)),
         ?_test(test_tool_with_schema(Server)),
         ?_test(test_prompt_with_args(Server)),
         ?_test(test_resource_subscription(Server)),
         ?_test(test_progress_reporting(Server))]
     end}.

setup_advanced() ->
    Capabilities =
        #mcp_server_capabilities{resources = #mcp_capability{enabled = true},
                                 tools = #mcp_capability{enabled = true},
                                 prompts = #mcp_capability{enabled = true}},
    {ok, Server} = erlmcp_server:start_link({stdio, []}, Capabilities),

    erlmcp_server:add_resource_template(Server,
                                        <<"test://{id}">>,
                                        <<"Test Template">>,
                                        fun(Uri) ->
                                           #mcp_content{type = <<"text">>,
                                                        text =
                                                            <<"Template content for ", Uri/binary>>,
                                                        mime_type = <<"text/plain">>}
                                        end),

    Schema =
        #{<<"type">> => <<"object">>,
          <<"properties">> => #{<<"value">> => #{<<"type">> => <<"string">>}},
          <<"required">> => [<<"value">>]},

    erlmcp_server:add_tool_with_schema(Server,
                                       <<"validate_test">>,
                                       fun(#{<<"value">> := Value}) ->
                                          #mcp_content{type = <<"text">>,
                                                       text = <<"Validated: ", Value/binary>>,
                                                       mime_type = <<"text/plain">>}
                                       end,
                                       Schema),

    PromptArgs =
        [#mcp_prompt_argument{name = <<"input">>,
                              description = <<"Test input">>,
                              required = true}],

    erlmcp_server:add_prompt_with_args(Server,
                                       <<"test_prompt">>,
                                       fun(#{<<"input">> := Input}) ->
                                          [#{<<"role">> => <<"user">>,
                                             <<"content">> =>
                                                 #{<<"type">> => <<"text">>,
                                                   <<"text">> =>
                                                       <<"Test prompt with input: ",
                                                         Input/binary>>}}]
                                       end,
                                       PromptArgs),

    Server.

cleanup(Server) ->
    erlmcp_server:stop(Server).

test_resource_template(Server) ->
    ?assertEqual(ok,
                 erlmcp_server:add_resource_template(Server,
                                                     <<"dynamic://{path}">>,
                                                     <<"Dynamic">>,
                                                     fun(_Uri) -> <<"dynamic content">> end)).

test_tool_with_schema(Server) ->
    Schema =
        #{<<"type">> => <<"object">>,
          <<"properties">> => #{<<"test">> => #{<<"type">> => <<"string">>}}},
    ?assertEqual(ok,
                 erlmcp_server:add_tool_with_schema(Server,
                                                    <<"schema_tool">>,
                                                    fun(_Args) -> <<"result">> end,
                                                    Schema)).

test_prompt_with_args(Server) ->
    Args = [#mcp_prompt_argument{name = <<"param">>, required = true}],
    ?assertEqual(ok,
                 erlmcp_server:add_prompt_with_args(Server,
                                                    <<"test_prompt_args">>,
                                                    fun(_Args) ->
                                                       [#{<<"role">> => <<"user">>,
                                                          <<"content">> => <<"test">>}]
                                                    end,
                                                    Args)).

test_resource_subscription(Server) ->
    ?assertEqual(ok, erlmcp_server:subscribe_resource(Server, <<"test://resource">>, self())),
    ?assertEqual(ok, erlmcp_server:unsubscribe_resource(Server, <<"test://resource">>)).

test_progress_reporting(Server) ->
    ?assertEqual(ok, erlmcp_server:report_progress(Server, <<"token1">>, 50.0, 100.0)).
