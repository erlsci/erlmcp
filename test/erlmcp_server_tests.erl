-module(erlmcp_server_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Helpers
%%====================================================================

start_server(Config) ->
    {ok, Pid} = erlmcp_server:start_link(Config),
    Pid.

stop_server(Pid) ->
    gen_server:stop(Pid).

make_tool(Name) ->
    #{name => Name, description => <<"test tool">>,
      handler => fun(_, _) -> {ok, [#{type => <<"text">>, text => <<"ok">>}]} end}.

make_resource(Uri) ->
    #{uri => Uri, name => <<"test">>,
      handler => fun(_, _) -> {ok, [#{uri => Uri, text => <<"content">>}]} end}.

make_prompt(Name) ->
    #{name => Name, description => <<"test prompt">>,
      handler => fun(_, _) -> {ok, #{<<"messages">> => []}} end}.

%%====================================================================
%% Tests — P6M1-1: server exists and owns catalog
%%====================================================================

start_empty_server_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    ?assertEqual(#{}, erlmcp_server:get_tools(Tab)),
    ?assertEqual(#{}, erlmcp_server:get_resources(Tab)),
    ?assertEqual(#{}, erlmcp_server:get_prompts(Tab)),
    stop_server(Pid).

register_tool_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    Tool = make_tool(<<"add">>),
    ok = erlmcp_server:register_tool(Pid, Tool),
    ?assertMatch({ok, #{name := <<"add">>}}, erlmcp_server:get_tool(Tab, <<"add">>)),
    ?assertEqual(1, maps:size(erlmcp_server:get_tools(Tab))),
    stop_server(Pid).

unregister_tool_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    ok = erlmcp_server:register_tool(Pid, make_tool(<<"rm">>)),
    ok = erlmcp_server:unregister_tool(Pid, <<"rm">>),
    ?assertEqual(error, erlmcp_server:get_tool(Tab, <<"rm">>)),
    stop_server(Pid).

register_resource_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    ok = erlmcp_server:register_resource(Pid, make_resource(<<"file:///a">>)),
    ?assertMatch({ok, _}, erlmcp_server:get_resource(Tab, <<"file:///a">>)),
    stop_server(Pid).

unregister_resource_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    ok = erlmcp_server:register_resource(Pid, make_resource(<<"file:///b">>)),
    ok = erlmcp_server:unregister_resource(Pid, <<"file:///b">>),
    ?assertEqual(error, erlmcp_server:get_resource(Tab, <<"file:///b">>)),
    stop_server(Pid).

register_prompt_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    ok = erlmcp_server:register_prompt(Pid, make_prompt(<<"greet">>)),
    ?assertMatch({ok, _}, erlmcp_server:get_prompt(Tab, <<"greet">>)),
    stop_server(Pid).

unregister_prompt_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    ok = erlmcp_server:register_prompt(Pid, make_prompt(<<"bye">>)),
    ok = erlmcp_server:unregister_prompt(Pid, <<"bye">>),
    ?assertEqual(error, erlmcp_server:get_prompt(Tab, <<"bye">>)),
    stop_server(Pid).

register_resource_template_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    Spec = #{uri_template => <<"file:///{path}">>, name => <<"files">>,
              handler => fun(_, _) -> {ok, []} end},
    ok = erlmcp_server:register_resource_template(Pid, Spec),
    ?assertEqual(1, maps:size(erlmcp_server:get_resource_templates(Tab))),
    stop_server(Pid).

server_info_test() ->
    Pid = start_server(#{name => <<"myserver">>, version => <<"1.0">>}),
    Tab = erlmcp_server:catalog_table(Pid),
    Info = erlmcp_server:get_server_info(Tab),
    ?assertEqual(<<"myserver">>, erlmcp_model:info_name(Info)),
    ?assertEqual(<<"1.0">>, erlmcp_model:info_version(Info)),
    stop_server(Pid).

%%====================================================================
%% Tests — P6M1-8: config-driven registration
%%====================================================================

config_driven_tools_test() ->
    Tools = [make_tool(<<"t1">>), make_tool(<<"t2">>)],
    Pid = start_server(#{tools => Tools}),
    Tab = erlmcp_server:catalog_table(Pid),
    ?assertEqual(2, maps:size(erlmcp_server:get_tools(Tab))),
    ?assertMatch({ok, _}, erlmcp_server:get_tool(Tab, <<"t1">>)),
    ?assertMatch({ok, _}, erlmcp_server:get_tool(Tab, <<"t2">>)),
    stop_server(Pid).

config_driven_resources_test() ->
    Resources = [make_resource(<<"file:///r1">>), make_resource(<<"file:///r2">>)],
    Pid = start_server(#{resources => Resources}),
    Tab = erlmcp_server:catalog_table(Pid),
    ?assertEqual(2, maps:size(erlmcp_server:get_resources(Tab))),
    stop_server(Pid).

config_driven_prompts_test() ->
    Prompts = [make_prompt(<<"p1">>), make_prompt(<<"p2">>)],
    Pid = start_server(#{prompts => Prompts}),
    Tab = erlmcp_server:catalog_table(Pid),
    ?assertEqual(2, maps:size(erlmcp_server:get_prompts(Tab))),
    stop_server(Pid).

config_driven_full_catalog_test() ->
    Pid = start_server(#{
        tools => [make_tool(<<"t">>)],
        resources => [make_resource(<<"file:///r">>)],
        prompts => [make_prompt(<<"p">>)]
    }),
    Tab = erlmcp_server:catalog_table(Pid),
    ?assertEqual(1, maps:size(erlmcp_server:get_tools(Tab))),
    ?assertEqual(1, maps:size(erlmcp_server:get_resources(Tab))),
    ?assertEqual(1, maps:size(erlmcp_server:get_prompts(Tab))),
    stop_server(Pid).

%%====================================================================
%% Tests — session notification
%%====================================================================

session_notification_on_register_test() ->
    Pid = start_server(#{}),
    ok = erlmcp_server:register_session(Pid, self()),
    ok = erlmcp_server:register_tool(Pid, make_tool(<<"n">>)),
    receive
        {catalog_changed, <<"notifications/tools/list_changed">>} -> ok
    after 1000 ->
        ?assert(false)
    end,
    stop_server(Pid).

session_cleanup_on_down_test() ->
    Pid = start_server(#{}),
    Sess = spawn_link(fun() -> receive stop -> ok end end),
    ok = erlmcp_server:register_session(Pid, Sess),
    Sess ! stop,
    timer:sleep(50),
    ok = erlmcp_server:register_tool(Pid, make_tool(<<"x">>)),
    receive
        {catalog_changed, _} -> ?assert(false)
    after 100 ->
        ok
    end,
    stop_server(Pid).

unregister_session_test() ->
    Pid = start_server(#{}),
    ok = erlmcp_server:register_session(Pid, self()),
    ok = erlmcp_server:unregister_session(Pid, self()),
    ok = erlmcp_server:register_tool(Pid, make_tool(<<"y">>)),
    receive
        {catalog_changed, _} -> ?assert(false)
    after 100 ->
        ok
    end,
    stop_server(Pid).

unregister_resource_template_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    Spec = #{uri_template => <<"tmpl/{x}">>, name => <<"t">>,
              handler => fun(_, _) -> {ok, []} end},
    ok = erlmcp_server:register_resource_template(Pid, Spec),
    ok = erlmcp_server:unregister_resource_template(Pid, <<"tmpl/{x}">>),
    ?assertEqual(#{}, erlmcp_server:get_resource_templates(Tab)),
    stop_server(Pid).

register_handler_module_test() ->
    Pid = start_server(#{handler => test_calc_handler}),
    Tab = erlmcp_server:catalog_table(Pid),
    ?assertMatch({ok, _}, erlmcp_server:get_tool(Tab, <<"add">>)),
    stop_server(Pid).

register_handler_via_api_test() ->
    Pid = start_server(#{}),
    Tab = erlmcp_server:catalog_table(Pid),
    ok = erlmcp_server:register_handler(Pid, test_calc_handler),
    ?assertMatch({ok, _}, erlmcp_server:get_tool(Tab, <<"add">>)),
    stop_server(Pid).

get_undefined_table_test() ->
    ?assertEqual(#{}, erlmcp_server:get_tools(undefined)),
    ?assertEqual(#{}, erlmcp_server:get_resources(undefined)),
    ?assertEqual(#{}, erlmcp_server:get_prompts(undefined)),
    ?assertEqual(#{}, erlmcp_server:get_resource_templates(undefined)),
    ?assertEqual(#{}, erlmcp_server:get_handlers(undefined)),
    ?assertEqual(#{}, erlmcp_server:get_capabilities(undefined)),
    ?assertEqual(error, erlmcp_server:get_tool(undefined, <<"x">>)),
    ?assertEqual(error, erlmcp_server:get_resource(undefined, <<"x">>)),
    ?assertEqual(error, erlmcp_server:get_prompt(undefined, <<"x">>)).

server_info_default_test() ->
    Info = erlmcp_server:get_server_info(undefined),
    ?assertEqual(<<"erlmcp">>, erlmcp_model:info_name(Info)).

unknown_request_test() ->
    Pid = start_server(#{}),
    ?assertEqual({error, unknown_request}, gen_server:call(Pid, bogus)),
    stop_server(Pid).

capabilities_in_config_test() ->
    Pid = start_server(#{capabilities => #{<<"tools">> => true}}),
    Tab = erlmcp_server:catalog_table(Pid),
    ?assertEqual(#{<<"tools">> => true}, erlmcp_server:get_capabilities(Tab)),
    stop_server(Pid).

handlers_in_config_test() ->
    Pid = start_server(#{handlers => #{<<"custom">> => fun(_, _) -> ok end}}),
    Tab = erlmcp_server:catalog_table(Pid),
    ?assertEqual(1, maps:size(erlmcp_server:get_handlers(Tab))),
    stop_server(Pid).

%%====================================================================
%% Registration validation
%%====================================================================

validate_tool_ok_test() ->
    Pid = start_server(#{}),
    ok = erlmcp_server:register_tool(Pid, make_tool(<<"v">>)),
    stop_server(Pid).

validate_tool_missing_name_test() ->
    Pid = start_server(#{}),
    ?assertMatch({error, {invalid_tool_spec, {missing, name}}},
        erlmcp_server:register_tool(Pid, #{description => <<"d">>,
            handler => fun(_, _) -> ok end})),
    stop_server(Pid).

validate_tool_missing_handler_test() ->
    Pid = start_server(#{}),
    ?assertMatch({error, {invalid_tool_spec, missing_handler}},
        erlmcp_server:register_tool(Pid, #{name => <<"t">>, description => <<"d">>})),
    stop_server(Pid).

validate_resource_ok_test() ->
    Pid = start_server(#{}),
    ok = erlmcp_server:register_resource(Pid, make_resource(<<"file:///ok">>)),
    stop_server(Pid).

validate_resource_missing_uri_test() ->
    Pid = start_server(#{}),
    ?assertMatch({error, {invalid_resource_spec, {missing, uri}}},
        erlmcp_server:register_resource(Pid, #{name => <<"r">>,
            handler => fun(_) -> ok end})),
    stop_server(Pid).

validate_resource_missing_handler_test() ->
    Pid = start_server(#{}),
    ?assertMatch({error, {invalid_resource_spec, missing_handler}},
        erlmcp_server:register_resource(Pid, #{uri => <<"x://a">>, name => <<"r">>})),
    stop_server(Pid).

validate_resource_template_ok_test() ->
    Pid = start_server(#{}),
    ok = erlmcp_server:register_resource_template(Pid,
        #{uri_template => <<"x://{id}">>, name => <<"t">>,
          handler => fun(_, _) -> ok end}),
    stop_server(Pid).

validate_resource_template_missing_uri_template_test() ->
    Pid = start_server(#{}),
    ?assertMatch({error, {invalid_resource_template_spec, {missing, uri_template}}},
        erlmcp_server:register_resource_template(Pid,
            #{name => <<"t">>, handler => fun(_, _) -> ok end})),
    stop_server(Pid).

validate_prompt_ok_test() ->
    Pid = start_server(#{}),
    ok = erlmcp_server:register_prompt(Pid, make_prompt(<<"vp">>)),
    stop_server(Pid).

validate_prompt_missing_name_test() ->
    Pid = start_server(#{}),
    ?assertMatch({error, {invalid_prompt_spec, {missing, name}}},
        erlmcp_server:register_prompt(Pid, #{handler => fun(_, _) -> ok end})),
    stop_server(Pid).

validate_prompt_missing_handler_test() ->
    Pid = start_server(#{}),
    ?assertMatch({error, {invalid_prompt_spec, missing_handler}},
        erlmcp_server:register_prompt(Pid, #{name => <<"p">>})),
    stop_server(Pid).
