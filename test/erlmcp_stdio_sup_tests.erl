-module(erlmcp_stdio_sup_tests).

-include_lib("eunit/include/eunit.hrl").

start_link_and_serve_test() ->
    ReadFun = fun() -> receive after 60000 -> eof end end,
    Config = #{
        name => <<"sup-test">>, version => <<"1.0">>,
        read_fun => ReadFun
    },
    {ok, Sup} = erlmcp_stdio_sup:start_link(Config),
    unlink(Sup),
    Children = supervisor:which_children(Sup),
    ?assertMatch({server, _, _, _}, lists:keyfind(server, 1, Children)),
    ?assertMatch({transport, _, _, _}, lists:keyfind(transport, 1, Children)),
    ?assertMatch({session, _, _, _}, lists:keyfind(session, 1, Children)),
    ok = erlmcp_stdio_sup:serve(Sup),
    exit(Sup, shutdown),
    timer:sleep(50).

serve_transport_not_found_test() ->
    {ok, Sup} = supervisor:start_link(erlmcp_stdio_sup, []),
    unlink(Sup),
    ?assertEqual({error, transport_not_found}, erlmcp_stdio_sup:serve(Sup)),
    exit(Sup, shutdown),
    timer:sleep(50).

wire_children_bad_server_config_test() ->
    process_flag(trap_exit, true),
    Result = erlmcp_stdio_sup:start_link(#{
        name => not_a_binary, version => <<"1.0">>
    }),
    ?assertMatch({error, _}, Result),
    flush_exits(),
    process_flag(trap_exit, false).

flush_exits() ->
    receive {'EXIT', _, _} -> flush_exits()
    after 100 -> ok
    end.
