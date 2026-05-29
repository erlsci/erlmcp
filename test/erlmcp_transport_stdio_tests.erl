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
%% gen_server — paused start (no reader until serve)
%%====================================================================

start_stop_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self()
    }),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

serve_starts_reader_test() ->
    Counter = atomics:new(1, [{signed, false}]),
    ReadFun = fun() ->
        case atomics:add_get(Counter, 1, 1) of
            1 -> "hello\n";
            _ -> eof
        end
    end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    Ref = monitor(process, Pid),
    ok = erlmcp_transport_stdio:set_session(Pid, self()),
    ok = erlmcp_transport_stdio:serve(Pid),
    receive {transport_data, <<"hello">>, _Responder} -> ok
    after 2000 -> ?assert(false) end,
    receive {'DOWN', Ref, process, Pid, normal} -> ok
    after 2000 -> ?assert(false) end.

simulate_input_test() ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>
    }),
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{}),
    Responder = erlmcp_reply:new_device(Pid),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    ok = erlmcp_transport_stdio:set_session(Pid, Session),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ok = erlmcp_transport_stdio:simulate_input(Pid, InitReq),
    timer:sleep(100),
    ?assertEqual(operational, gen_statem:call(Session, get_state)),
    erlmcp_transport_stdio:close(Pid),
    gen_statem:stop(Session),
    gen_server:stop(Srv).

outbound_via_info_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self()
    }),
    Pid ! {send, <<"outbound data">>},
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

line_delivery_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self()
    }),
    ok = erlmcp_transport_stdio:set_session(Pid, self()),
    Pid ! {line, <<"hello">>},
    receive {transport_data, <<"hello">>, _Responder} -> ok
    after 1000 -> ?assert(false)
    end,
    erlmcp_transport_stdio:close(Pid).

validate_config_test() ->
    ?assertEqual(ok, erlmcp_transport_stdio:validate_config(#{session => self()})),
    ?assertMatch({error, _}, erlmcp_transport_stdio:validate_config(#{})),
    ?assertMatch({error, _}, erlmcp_transport_stdio:validate_config(not_a_map)).

unknown_call_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self()
    }),
    ?assertMatch({error, _}, gen_server:call(Pid, unknown_request)),
    erlmcp_transport_stdio:close(Pid).

unknown_cast_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self()
    }),
    gen_server:cast(Pid, unknown),
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

unknown_info_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self()
    }),
    Pid ! unknown_message,
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

terminate_no_reader_test() ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self()
    }),
    Ref = monitor(process, Pid),
    erlmcp_transport_stdio:close(Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok
    after 2000 -> ?assert(false)
    end.

%%====================================================================
%% Injected reader — exercises read_loop via serve/1
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
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    Ref = monitor(process, Pid),
    ok = erlmcp_transport_stdio:set_session(Pid, self()),
    ok = erlmcp_transport_stdio:serve(Pid),
    receive {transport_data, <<"hello world">>, _} -> ok
    after 2000 -> ?assert(false) end,
    receive {transport_data, <<"binary line">>, _} -> ok
    after 2000 -> ?assert(false) end,
    receive {'DOWN', Ref, process, Pid, normal} -> ok
    after 2000 -> ?assert(false) end.

reader_skips_blank_lines_test() ->
    Counter = atomics:new(1, [{signed, false}]),
    ReadFun = fun() ->
        case atomics:add_get(Counter, 1, 1) of
            1 -> "\n";
            2 -> "real\n";
            _ -> eof
        end
    end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    Ref = monitor(process, Pid),
    ok = erlmcp_transport_stdio:set_session(Pid, self()),
    ok = erlmcp_transport_stdio:serve(Pid),
    receive {transport_data, <<"real">>, _} -> ok
    after 2000 -> ?assert(false) end,
    receive {'DOWN', Ref, process, Pid, normal} -> ok
    after 2000 -> ?assert(false) end.

reader_error_stops_transport_test() ->
    ReadFun = fun() -> {error, eio} end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self(), read_fun => ReadFun
    }),
    ok = erlmcp_transport_stdio:serve(Pid),
    unlink(Pid),
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, {reader_died, {read_error, eio}}} -> ok
    after 2000 -> ?assert(false)
    end.

reader_eof_stops_transport_test() ->
    ReadFun = fun() -> eof end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self(), read_fun => ReadFun
    }),
    ok = erlmcp_transport_stdio:serve(Pid),
    unlink(Pid),
    Ref = monitor(process, Pid),
    receive {'DOWN', Ref, process, Pid, normal} -> ok
    after 2000 -> ?assert(false)
    end.

terminate_kills_reader_test() ->
    ReadFun = fun() -> receive after 60000 -> eof end end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self(), read_fun => ReadFun
    }),
    ok = erlmcp_transport_stdio:serve(Pid),
    unlink(Pid),
    Ref = monitor(process, Pid),
    erlmcp_transport_stdio:close(Pid),
    receive {'DOWN', Ref, process, Pid, _} -> ok
    after 2000 -> ?assert(false)
    end.

already_serving_test() ->
    ReadFun = fun() -> receive after 60000 -> eof end end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self(), read_fun => ReadFun
    }),
    ok = erlmcp_transport_stdio:serve(Pid),
    ?assertEqual({error, already_serving}, erlmcp_transport_stdio:serve(Pid)),
    erlmcp_transport_stdio:close(Pid).
