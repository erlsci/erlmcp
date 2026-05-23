-module(erlmcp_transport_stdio_tests).

-include_lib("eunit/include/eunit.hrl").

start_stop_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

send_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    ok = erlmcp_transport_stdio:send(Pid, <<"hello">>),
    erlmcp_transport_stdio:close(Pid).

simulate_input_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => Server, test_mode => true
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ok = erlmcp_transport_stdio:simulate_input(Pid, InitReq),
    timer:sleep(100),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    erlmcp_transport_stdio:close(Pid),
    gen_statem:stop(Server).

outbound_via_info_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    Pid ! {send, <<"outbound data">>},
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

validate_config_test() ->
    ?assertEqual(ok, erlmcp_transport_stdio:validate_config(#{session => self()})),
    ?assertMatch({error, _}, erlmcp_transport_stdio:validate_config(#{})),
    ?assertMatch({error, _}, erlmcp_transport_stdio:validate_config(not_a_map)).

unknown_call_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    ?assertMatch({error, _}, gen_server:call(Pid, unknown_request)),
    erlmcp_transport_stdio:close(Pid).

unknown_cast_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    gen_server:cast(Pid, unknown),
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

unknown_info_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    Pid ! unknown_message,
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

terminate_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    Ref = monitor(process, Pid),
    erlmcp_transport_stdio:close(Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok
    after 2000 -> ?assert(false)
    end.

line_delivery_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    Pid ! {line, <<"hello">>},
    receive {transport_data, <<"hello">>} -> ok
    after 1000 -> ?assert(false)
    end,
    erlmcp_transport_stdio:close(Pid).

