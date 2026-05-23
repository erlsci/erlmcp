-module(erlmcp_transport_stdio_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Pure function tests — no I/O, no processes
%%====================================================================

process_raw_input_eof_test() ->
    ?assertEqual(eof, erlmcp_transport_stdio:process_raw_input(eof)).

process_raw_input_error_test() ->
    ?assertEqual({error, eio}, erlmcp_transport_stdio:process_raw_input({error, eio})).

process_raw_input_list_test() ->
    ?assertEqual({deliver, <<"hello">>},
        erlmcp_transport_stdio:process_raw_input("hello")).

process_raw_input_binary_test() ->
    ?assertEqual({deliver, <<"hello">>},
        erlmcp_transport_stdio:process_raw_input(<<"hello">>)).

prepare_line_normal_test() ->
    ?assertEqual({send, <<"hello">>},
        erlmcp_transport_stdio:prepare_line(<<"hello\n">>)).

prepare_line_crlf_test() ->
    ?assertEqual({send, <<"hello">>},
        erlmcp_transport_stdio:prepare_line(<<"hello\r\n">>)).

prepare_line_empty_test() ->
    ?assertEqual(skip, erlmcp_transport_stdio:prepare_line(<<"\n">>)).

prepare_line_blank_test() ->
    ?assertEqual(skip, erlmcp_transport_stdio:prepare_line(<<>>)).

%%====================================================================
%% gen_server — test_mode (no I/O)
%%====================================================================

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
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
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

line_delivery_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    Pid ! {line, <<"hello">>},
    receive {transport_data, <<"hello">>} -> ok
    after 1000 -> ?assert(false)
    end,
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

terminate_test_mode_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), test_mode => true
    }),
    Ref = monitor(process, Pid),
    erlmcp_transport_stdio:close(Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok
    after 2000 -> ?assert(false)
    end.

%%====================================================================
%% Injected reader — exercises read_loop, deliver_line, EXIT handlers
%%====================================================================

reader_delivers_lines_test() ->
    Counter = atomics:new(1, [{signed, false}]),
    ReadFun = fun() ->
        case atomics:add_get(Counter, 1, 1) of
            1 -> "hello world\n";
            2 -> <<"binary line\r\n">>;
            _ -> eof
        end
    end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    receive {transport_data, <<"hello world">>} -> ok
    after 2000 -> ?assert(false) end,
    receive {transport_data, <<"binary line">>} -> ok
    after 2000 -> ?assert(false) end,
    timer:sleep(100),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

reader_skips_blank_lines_test() ->
    Counter = atomics:new(1, [{signed, false}]),
    ReadFun = fun() ->
        case atomics:add_get(Counter, 1, 1) of
            1 -> "\n";
            2 -> "real\n";
            _ -> eof
        end
    end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    receive {transport_data, <<"real">>} -> ok
    after 2000 -> ?assert(false) end,
    timer:sleep(100),
    erlmcp_transport_stdio:close(Pid).

reader_error_stops_transport_test() ->
    ReadFun = fun() -> {error, eio} end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, {reader_died, {read_error, eio}}} -> ok
    after 2000 -> ?assert(false)
    end.

reader_eof_graceful_test() ->
    ReadFun = fun() -> eof end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    timer:sleep(100),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

terminate_kills_reader_test() ->
    ReadFun = fun() -> receive after 60000 -> eof end end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(test_stdio, #{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    timer:sleep(50),
    Ref = monitor(process, Pid),
    erlmcp_transport_stdio:close(Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok
    after 2000 -> ?assert(false)
    end.

