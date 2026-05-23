-module(erlmcp_transport_tcp_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    ok = meck:new(gen_tcp, [unstick, passthrough]),
    ok.

cleanup(_) ->
    meck:unload(gen_tcp),
    ok.

tcp_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        fun start_link_connects/1,
        fun send_when_connected/1,
        fun send_when_disconnected/1,
        fun close_pid/1,
        fun close_state_connected/1,
        fun close_state_disconnected/1,
        fun tcp_data_delivery/1,
        fun tcp_closed_reconnects/1,
        fun tcp_error_reconnects/1,
        fun connect_failure_schedules_reconnect/1,
        fun max_reconnect_reached/1,
        fun owner_death_stops/1,
        fun get_state_call/1,
        fun unknown_call/1,
        fun unknown_cast/1,
        fun unknown_info/1,
        fun code_change_noop/1,
        fun send_state_api/1,
        fun reconnect_via_connect_call/1,
        fun socket_exit_reconnects/1,
        fun extract_messages_partial/1,
        fun validate_config_test_/1,
        fun disconnect_already_disconnected/1,
        fun reconnect_already_scheduled/1,
        fun send_failure_triggers_error/1,
        fun tcp_options_with_extras/1
    ]}.

mock_connect_ok() ->
    FakeSocket = make_ref(),
    meck:expect(gen_tcp, connect, fun(_H, _P, _O, _T) -> {ok, FakeSocket} end),
    meck:expect(gen_tcp, close, fun(_) -> ok end),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    FakeSocket.

mock_connect_fail() ->
    meck:expect(gen_tcp, connect, fun(_H, _P, _O, _T) -> {error, econnrefused} end).

start_tcp(Owner) ->
    FakeSocket = mock_connect_ok(),
    {ok, Pid} = erlmcp_transport_tcp:start_link(#{
        host => "localhost", port => 9999, owner => Owner,
        max_reconnect_attempts => 3
    }),
    unlink(Pid),
    timer:sleep(50),
    case Owner =:= self() of
        true -> receive {transport_connected, Pid} -> ok after 1000 -> ok end;
        false -> timer:sleep(50)
    end,
    {Pid, FakeSocket}.

start_link_connects(_) ->
    {"start_link connects and notifies owner", fun() ->
        {Pid, _} = start_tcp(self()),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

send_when_connected(_) ->
    {"send/2 succeeds when connected", fun() ->
        {Pid, _} = start_tcp(self()),
        ?assertEqual(ok, erlmcp_transport_tcp:send(Pid, <<"hello">>)),
        erlmcp_transport_tcp:close(Pid)
    end}.

send_when_disconnected(_) ->
    {"send/2 returns error when disconnected", fun() ->
        mock_connect_fail(),
        {ok, Pid} = erlmcp_transport_tcp:start_link(#{
            host => "localhost", port => 9999, owner => self(),
            max_reconnect_attempts => 1
        }),
        timer:sleep(100),
        ?assertEqual({error, not_connected}, erlmcp_transport_tcp:send(Pid, <<"x">>)),
        erlmcp_transport_tcp:close(Pid)
    end}.

close_pid(_) ->
    {"close/1 with pid stops the process", fun() ->
        {Pid, _} = start_tcp(self()),
        Ref = monitor(process, Pid),
        erlmcp_transport_tcp:close(Pid),
        receive {'DOWN', Ref, process, Pid, _} -> ok after 2000 -> ?assert(false) end
    end}.

close_state_connected(_) ->
    {"close/1 with state closes socket", fun() ->
        FakeSocket = make_ref(),
        meck:expect(gen_tcp, close, fun(_) -> ok end),
        ?assertEqual(ok, erlmcp_transport_tcp:close(#{socket => FakeSocket}))
    end}.

close_state_disconnected(_) ->
    {"close/1 with no socket is ok", fun() ->
        ?assertEqual(ok, erlmcp_transport_tcp:close(#{socket => undefined})),
        ?assertEqual(ok, erlmcp_transport_tcp:close(#{}))
    end}.

tcp_data_delivery(_) ->
    {"inbound tcp data delivered to owner", fun() ->
        {Pid, FakeSocket} = start_tcp(self()),
        Pid ! {tcp, FakeSocket, <<"test message\n">>},
        receive {transport_data, <<"test message">>} -> ok
        after 1000 -> ?assert(false)
        end,
        erlmcp_transport_tcp:close(Pid)
    end}.

tcp_closed_reconnects(_) ->
    {"tcp_closed triggers reconnect", fun() ->
        {Pid, FakeSocket} = start_tcp(self()),
        Pid ! {tcp_closed, FakeSocket},
        receive {transport_disconnected, Pid, normal} -> ok
        after 1000 -> ?assert(false)
        end,
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

tcp_error_reconnects(_) ->
    {"tcp_error triggers reconnect", fun() ->
        {Pid, FakeSocket} = start_tcp(self()),
        Pid ! {tcp_error, FakeSocket, econnreset},
        receive {transport_disconnected, Pid, econnreset} -> ok
        after 1000 -> ?assert(false)
        end,
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

connect_failure_schedules_reconnect(_) ->
    {"connection failure schedules reconnect", fun() ->
        mock_connect_fail(),
        {ok, Pid} = erlmcp_transport_tcp:start_link(#{
            host => "localhost", port => 9999, owner => self(),
            max_reconnect_attempts => 3
        }),
        timer:sleep(100),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

max_reconnect_reached(_) ->
    {"max reconnect attempts stops retrying", fun() ->
        mock_connect_fail(),
        {ok, Pid} = erlmcp_transport_tcp:start_link(#{
            host => "localhost", port => 9999, owner => self(),
            max_reconnect_attempts => 1
        }),
        timer:sleep(200),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

owner_death_stops(_) ->
    {"owner death stops transport", fun() ->
        Owner = spawn(fun() -> receive stop -> ok end end),
        {Pid, _} = start_tcp(Owner),
        Ref = monitor(process, Pid),
        Owner ! stop,
        receive {'DOWN', Ref, process, Pid, {owner_died, _}} -> ok
        after 2000 -> ?assert(false)
        end
    end}.

get_state_call(_) ->
    {"get_state returns state", fun() ->
        {Pid, _} = start_tcp(self()),
        {ok, State} = gen_server:call(Pid, get_state),
        ?assert(is_map(State)),
        ?assertEqual(true, maps:get(connected, State)),
        erlmcp_transport_tcp:close(Pid)
    end}.

unknown_call(_) ->
    {"unknown call returns error", fun() ->
        {Pid, _} = start_tcp(self()),
        ?assertEqual({error, unknown_request}, gen_server:call(Pid, foo)),
        erlmcp_transport_tcp:close(Pid)
    end}.

unknown_cast(_) ->
    {"unknown cast is ignored", fun() ->
        {Pid, _} = start_tcp(self()),
        gen_server:cast(Pid, foo),
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

unknown_info(_) ->
    {"unknown info is ignored", fun() ->
        {Pid, _} = start_tcp(self()),
        Pid ! {random, message},
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

code_change_noop(_) ->
    {"code_change returns ok", fun() ->
        ?assertEqual({ok, state}, erlmcp_transport_tcp:code_change(old, state, extra))
    end}.

send_state_api(_) ->
    {"send/2 with state map works", fun() ->
        FakeSocket = make_ref(),
        meck:expect(gen_tcp, send, fun(_, _) -> ok end),
        ?assertEqual(ok, erlmcp_transport_tcp:send(#{socket => FakeSocket}, <<"data">>)),
        meck:expect(gen_tcp, send, fun(_, _) -> {error, closed} end),
        ?assertMatch({error, _}, erlmcp_transport_tcp:send(#{socket => FakeSocket}, <<"data">>)),
        ?assertEqual({error, not_connected}, erlmcp_transport_tcp:send(#{socket => undefined}, <<"data">>))
    end}.

reconnect_via_connect_call(_) ->
    {"connect/2 triggers reconnection", fun() ->
        {Pid, _} = start_tcp(self()),
        ok = erlmcp_transport_tcp:connect(Pid, #{host => "other", port => 8888}),
        timer:sleep(100),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

socket_exit_reconnects(_) ->
    {"socket EXIT triggers reconnect", fun() ->
        {Pid, FakeSocket} = start_tcp(self()),
        Pid ! {'EXIT', FakeSocket, econnreset},
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

extract_messages_partial(_) ->
    {"partial messages buffered", fun() ->
        {Pid, FakeSocket} = start_tcp(self()),
        Pid ! {tcp, FakeSocket, <<"part1">>},
        timer:sleep(50),
        receive {transport_data, _} -> ?assert(false) after 100 -> ok end,
        Pid ! {tcp, FakeSocket, <<" part2\n">>},
        receive {transport_data, <<"part1 part2">>} -> ok
        after 1000 -> ?assert(false)
        end,
        erlmcp_transport_tcp:close(Pid)
    end}.

validate_config_test_(_) ->
    {"validate_config checks required keys", fun() ->
        ?assertEqual(ok, erlmcp_transport_tcp:validate_config(
            #{host => "h", port => 1, owner => self()})),
        ?assertMatch({error, _}, erlmcp_transport_tcp:validate_config(#{})),
        ?assertMatch({error, _}, erlmcp_transport_tcp:validate_config(#{host => "h"})),
        ?assertMatch({error, _}, erlmcp_transport_tcp:validate_config(not_a_map))
    end}.

disconnect_already_disconnected(_) ->
    {"disconnect when already disconnected is safe", fun() ->
        mock_connect_fail(),
        {ok, Pid} = erlmcp_transport_tcp:start_link(#{
            host => "localhost", port => 9999, owner => self(),
            max_reconnect_attempts => 1
        }),
        timer:sleep(200),
        Pid ! {tcp_closed, make_ref()},
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

reconnect_already_scheduled(_) ->
    {"reconnect when already scheduled does not duplicate", fun() ->
        {Pid, FakeSocket} = start_tcp(self()),
        Pid ! {tcp_closed, FakeSocket},
        receive {transport_disconnected, _, _} -> ok after 1000 -> ok end,
        Pid ! {tcp_error, make_ref(), econnreset},
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_tcp:close(Pid)
    end}.

send_failure_triggers_error(_) ->
    {"send failure triggers tcp_error", fun() ->
        _ = mock_connect_ok(),
        meck:expect(gen_tcp, send, fun(_, _) -> {error, closed} end),
        {ok, Pid} = erlmcp_transport_tcp:start_link(#{
            host => "localhost", port => 9999, owner => self(),
            max_reconnect_attempts => 3
        }),
        unlink(Pid),
        timer:sleep(50),
        receive {transport_connected, Pid} -> ok after 1000 -> ok end,
        {error, _} = erlmcp_transport_tcp:send(Pid, <<"data">>),
        timer:sleep(50),
        erlmcp_transport_tcp:close(Pid)
    end}.

tcp_options_with_extras(_) ->
    {"optional tcp options are passed through", fun() ->
        _ = mock_connect_ok(),
        {ok, Pid} = erlmcp_transport_tcp:start_link(#{
            host => "localhost", port => 9999, owner => self(),
            max_reconnect_attempts => 3,
            keepalive => true, nodelay => true, buffer_size => 32768
        }),
        unlink(Pid),
        timer:sleep(50),
        receive {transport_connected, Pid} -> ok after 1000 -> ok end,
        erlmcp_transport_tcp:close(Pid)
    end}.
