-module(erlmcp_sup_tests).

-include_lib("eunit/include/eunit.hrl").

app_start_stop_test() ->
    {ok, _} = application:ensure_all_started(jsx),
    {ok, _} = application:ensure_all_started(jesse),
    {ok, _} = application:ensure_all_started(erlmcp),
    ?assert(is_pid(whereis(erlmcp_sup))),
    ?assert(is_pid(whereis(erlmcp_registry))),
    ok = application:stop(erlmcp),
    timer:sleep(100).

sup_children_test() ->
    {ok, _} = application:ensure_all_started(jsx),
    {ok, _} = application:ensure_all_started(jesse),
    {ok, _} = application:ensure_all_started(erlmcp),
    Children = supervisor:which_children(erlmcp_sup),
    ChildIds = [Id || {Id, _, _, _} <- Children],
    ?assert(lists:member(erlmcp_registry, ChildIds)),
    ok = application:stop(erlmcp),
    timer:sleep(100).

server_sup_test() ->
    {ok, _} = application:ensure_all_started(jsx),
    {ok, _} = application:ensure_all_started(jesse),
    {ok, _} = application:ensure_all_started(erlmcp),
    Children = supervisor:which_children(erlmcp_sup),
    case lists:keyfind(erlmcp_server_sup, 1, Children) of
        {erlmcp_server_sup, Pid, _, _} when is_pid(Pid) ->
            ?assert(is_process_alive(Pid));
        _ -> ok
    end,
    ok = application:stop(erlmcp),
    timer:sleep(100).

registry_via_app_test() ->
    {ok, _} = application:ensure_all_started(jsx),
    {ok, _} = application:ensure_all_started(jesse),
    {ok, _} = application:ensure_all_started(erlmcp),
    ?assertEqual([], erlmcp_registry:list_servers()),
    ?assertEqual([], erlmcp_registry:list_transports()),
    ok = application:stop(erlmcp),
    timer:sleep(100).

sup_stop_server_not_found_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ?assertEqual(ok, erlmcp_sup:stop_server(nonexistent)),
    ok = application:stop(erlmcp),
    timer:sleep(100).

sup_stop_transport_not_found_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ?assertEqual(ok, erlmcp_sup:stop_transport(nonexistent)),
    ok = application:stop(erlmcp),
    timer:sleep(100).


