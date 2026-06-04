-module(erlmcp_http_sup_tests).

-include_lib("eunit/include/eunit.hrl").

start_link_creates_subtree_test() ->
    application:ensure_all_started(cowboy),
    Config = #{
        name => <<"sup_test">>,
        version => <<"0.1.0">>,
        port => 0,
        tools => [#{
            name => <<"test_tool">>,
            description => <<"Test">>,
            handler => fun(_Args, _Ctx) -> {ok, []} end
        }]
    },
    {ok, Sup} = erlmcp_http_sup:start_link(Config),
    Children = supervisor:which_children(Sup),
    ?assertNotEqual(false, lists:keyfind(server, 1, Children)),
    ?assertNotEqual(false, lists:keyfind(session_mgr, 1, Children)),
    {session_mgr, MgrPid, _, _} = lists:keyfind(session_mgr, 1, Children),
    {ok, Port} = erlmcp_http_session_mgr:get_port(MgrPid),
    ?assert(is_integer(Port)),
    ?assert(Port > 0),
    LRef = erlmcp_http_session_mgr:listener_ref(MgrPid),
    cowboy:stop_listener(LRef),
    unlink(Sup),
    exit(Sup, shutdown),
    timer:sleep(50).

get_port_via_sup_test() ->
    application:ensure_all_started(cowboy),
    Config = #{
        name => <<"port_test">>,
        version => <<"0.1.0">>,
        port => 0
    },
    {ok, Sup} = erlmcp_http_sup:start_link(Config),
    {ok, Port} = erlmcp_http_sup:get_port(Sup),
    ?assert(is_integer(Port)),
    ?assert(Port > 0),
    Children = supervisor:which_children(Sup),
    {session_mgr, MgrPid, _, _} = lists:keyfind(session_mgr, 1, Children),
    LRef = erlmcp_http_session_mgr:listener_ref(MgrPid),
    cowboy:stop_listener(LRef),
    unlink(Sup),
    exit(Sup, shutdown),
    timer:sleep(50).

init_callback_test() ->
    {ok, {SupFlags, Children}} = erlmcp_http_sup:init([]),
    ?assertEqual(rest_for_one, maps:get(strategy, SupFlags)),
    ?assertEqual([], Children).
