-module(erlmcp_infra_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Registry — cover all API paths
%%====================================================================

registry_start_stop_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ?assert(is_pid(whereis(erlmcp_registry))),
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_server_lifecycle_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ServerPid = spawn_link(fun() -> receive stop -> ok end end),
    ok = erlmcp_registry:register_server(test_srv, ServerPid, #{name => <<"test">>}),
    ?assertEqual({ok, {ServerPid, #{name => <<"test">>}}},
                 erlmcp_registry:find_server(test_srv)),
    [{test_srv, _}] = erlmcp_registry:list_servers(),
    ?assertEqual({error, already_registered},
                 erlmcp_registry:register_server(test_srv, ServerPid, #{})),
    ok = erlmcp_registry:unregister_server(test_srv),
    ?assertEqual({error, not_found}, erlmcp_registry:find_server(test_srv)),
    ok = erlmcp_registry:unregister_server(nonexistent),
    ServerPid ! stop,
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_transport_lifecycle_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    TransPid = spawn_link(fun() -> receive stop -> ok end end),
    ok = erlmcp_registry:register_transport(test_trans, TransPid,
        #{type => stdio}),
    ?assertEqual({ok, {TransPid, #{type => stdio}}},
                 erlmcp_registry:find_transport(test_trans)),
    [{test_trans, _}] = erlmcp_registry:list_transports(),
    ?assertEqual({error, already_registered},
                 erlmcp_registry:register_transport(test_trans, TransPid, #{})),
    ok = erlmcp_registry:unregister_transport(test_trans),
    ?assertEqual({error, not_found}, erlmcp_registry:find_transport(test_trans)),
    ok = erlmcp_registry:unregister_transport(nonexistent),
    TransPid ! stop,
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_binding_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    SPid = spawn_link(fun() -> receive stop -> ok end end),
    TPid = spawn_link(fun() -> receive stop -> ok end end),
    ok = erlmcp_registry:register_server(bind_srv, SPid, #{}),
    ok = erlmcp_registry:register_transport(bind_trans, TPid, #{}),
    ok = erlmcp_registry:bind_transport_to_server(bind_trans, bind_srv),
    ?assertEqual({ok, bind_srv},
                 erlmcp_registry:get_server_for_transport(bind_trans)),
    ?assertEqual({error, server_not_found},
                 erlmcp_registry:bind_transport_to_server(bind_trans, nonexistent)),
    ?assertEqual({error, transport_not_found},
                 erlmcp_registry:bind_transport_to_server(nonexistent, bind_srv)),
    ok = erlmcp_registry:unbind_transport(bind_trans),
    ?assertEqual({error, not_found},
                 erlmcp_registry:get_server_for_transport(bind_trans)),
    erlmcp_registry:unregister_server(bind_srv),
    erlmcp_registry:unregister_transport(bind_trans),
    SPid ! stop, TPid ! stop,
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_monitor_cleanup_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Pid = spawn(fun() -> receive stop -> ok end end),
    ok = erlmcp_registry:register_server(mon_srv, Pid, #{}),
    Pid ! stop,
    timer:sleep(100),
    ?assertEqual({error, not_found}, erlmcp_registry:find_server(mon_srv)),
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_transport_monitor_cleanup_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Pid = spawn(fun() -> receive stop -> ok end end),
    ok = erlmcp_registry:register_transport(mon_trans, Pid, #{}),
    Pid ! stop,
    timer:sleep(100),
    ?assertEqual({error, not_found}, erlmcp_registry:find_transport(mon_trans)),
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_auto_bind_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    SPid = spawn_link(fun() -> receive stop -> ok end end),
    TPid = spawn_link(fun() -> receive stop -> ok end end),
    ok = erlmcp_registry:register_server(ab_srv, SPid, #{}),
    ok = erlmcp_registry:register_transport(ab_trans, TPid,
        #{server_id => ab_srv}),
    ?assertEqual({ok, ab_srv},
                 erlmcp_registry:get_server_for_transport(ab_trans)),
    erlmcp_registry:unregister_server(ab_srv),
    erlmcp_registry:unregister_transport(ab_trans),
    SPid ! stop, TPid ! stop,
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_unknown_call_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ?assertEqual({error, unknown_request},
                 gen_server:call(erlmcp_registry, unknown_thing)),
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_unknown_cast_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    gen_server:cast(erlmcp_registry, unknown),
    timer:sleep(50),
    ?assert(is_pid(whereis(erlmcp_registry))),
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_unknown_info_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    erlmcp_registry ! unknown_msg,
    timer:sleep(50),
    ?assert(is_pid(whereis(erlmcp_registry))),
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_code_change_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ?assertEqual({ok, state}, erlmcp_registry:code_change(old, state, extra)),
    ok = application:stop(erlmcp),
    timer:sleep(100).

%%====================================================================
%% Supervision — session_sup, transport_sup
%%====================================================================

sup_tree_children_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Children = supervisor:which_children(erlmcp_sup),
    ?assert(length(Children) >= 1),
    ok = application:stop(erlmcp),
    timer:sleep(100).

%%====================================================================
%% Streamable HTTP stub
%%====================================================================

streamable_http_start_stop_test() ->
    {ok, Pid} = erlmcp_transport_streamable_http:start_link(#{}),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_streamable_http:close(Pid).

streamable_http_send_test() ->
    {ok, Pid} = erlmcp_transport_streamable_http:start_link(#{}),
    ?assertMatch({error, _}, erlmcp_transport_streamable_http:send(Pid, <<"data">>)),
    erlmcp_transport_streamable_http:close(Pid).

streamable_http_cast_info_test() ->
    {ok, Pid} = erlmcp_transport_streamable_http:start_link(#{}),
    gen_server:cast(Pid, unknown),
    Pid ! unknown,
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_streamable_http:close(Pid).

%%====================================================================
%% Sup tree — exercise via app start
%%====================================================================

sup_tree_via_app_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    SupChildren = supervisor:which_children(erlmcp_sup),
    ?assert(length(SupChildren) >= 3),
    ChildIds = [Id || {Id, _, _, _} <- SupChildren],
    ?assert(lists:member(erlmcp_registry, ChildIds)),
    ?assert(lists:member(erlmcp_server_sup, ChildIds)),
    ?assert(lists:member(erlmcp_transport_sup, ChildIds)),
    ok = application:stop(erlmcp),
    timer:sleep(100).
