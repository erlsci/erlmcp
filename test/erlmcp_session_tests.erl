-module(erlmcp_session_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Helpers — in-process transport bridge
%%====================================================================

%% A pair of transports that bridge client <-> server in the same process
%% without actual stdio. Each transport forwards {transport_data, Data}
%% to the other side's session.

start_bridge() ->
    ServerTransport = spawn_link(fun() -> bridge_loop(undefined) end),
    ClientTransport = spawn_link(fun() -> bridge_loop(undefined) end),
    {ServerTransport, ClientTransport}.

bridge_loop(Session) ->
    receive
        {set_session, Pid} ->
            bridge_loop(Pid);
        {set_peer, _Peer} ->
            bridge_loop(Session);
        {send, Data} when is_pid(Session) ->
            Session ! {bridge_data, Data},
            bridge_loop(Session);
        _ ->
            bridge_loop(Session)
    end.

setup_session_pair() ->
    {ServerTransport, ClientTransport} = start_bridge(),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => ServerTransport,
        name => <<"test-server">>,
        version => <<"1.0">>,
        capabilities => #{<<"tools">> => #{}},
        handlers => #{}
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => ClientTransport,
        name => <<"test-client">>,
        version => <<"1.0">>
    }),
    ServerTransport ! {set_session, Server},
    ClientTransport ! {set_session, Client},
    %% Wire: client transport send -> server session, and vice versa
    Forwarder = spawn_link(fun() -> forwarder_loop(Server, Client, ServerTransport, ClientTransport) end),
    {Server, Client, ServerTransport, ClientTransport, Forwarder}.

forwarder_loop(Server, Client, ServerTransport, ClientTransport) ->
    receive
        stop -> ok
    after 0 -> ok
    end,
    %% This forwarder is not needed — we use simulate_direct below
    forwarder_loop(Server, Client, ServerTransport, ClientTransport).

%%====================================================================
%% Direct bridge: send data between sessions without real transport
%%====================================================================

%% For testing, we bypass the transport and feed data directly
%% between sessions using gen_statem:cast.

initialize_direct_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test-server">>,
        version => <<"1.0">>,
        capabilities => #{<<"tools">> => #{}}
    }),
    InitRequest = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{<<"name">> => <<"test">>, <<"version">> => <<"1.0">>}
    }),
    erlmcp_server_session:send_message(Server, InitRequest),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    gen_statem:stop(Server).

pre_init_rejected_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test-server">>,
        version => <<"1.0">>
    }),
    ?assertEqual(uninitialized, gen_statem:call(Server, get_state)),
    PingRequest = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
    erlmcp_server_session:send_message(Server, PingRequest),
    timer:sleep(50),
    ?assertEqual(uninitialized, gen_statem:call(Server, get_state)),
    gen_statem:stop(Server).

worker_crash_isolation_test() ->
    CrashHandler = fun(_Params, _Ctx) -> error(intentional_crash) end,
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test-server">>,
        version => <<"1.0">>,
        capabilities => #{<<"tools">> => #{}},
        handlers => #{<<"crash/test">> => CrashHandler}
    }),
    InitRequest = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{<<"name">> => <<"test">>, <<"version">> => <<"1.0">>}
    }),
    erlmcp_server_session:send_message(Server, InitRequest),
    timer:sleep(50),
    CrashRequest = erlmcp_json_rpc:encode_request(2, <<"crash/test">>, #{}),
    erlmcp_server_session:send_message(Server, CrashRequest),
    timer:sleep(100),
    ?assert(is_process_alive(Server)),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    gen_statem:stop(Server).

cancellation_test() ->
    SlowHandler = fun(_Params, _Ctx) ->
        receive after 5000 -> {ok, #{}} end
    end,
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test-server">>,
        version => <<"1.0">>,
        capabilities => #{<<"tools">> => #{}},
        handlers => #{<<"slow/test">> => SlowHandler}
    }),
    InitRequest = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{<<"name">> => <<"test">>, <<"version">> => <<"1.0">>}
    }),
    erlmcp_server_session:send_message(Server, InitRequest),
    timer:sleep(50),
    SlowRequest = erlmcp_json_rpc:encode_request(2, <<"slow/test">>, #{}),
    erlmcp_server_session:send_message(Server, SlowRequest),
    timer:sleep(50),
    CancelNotification = erlmcp_json_rpc:encode_notification(
        <<"notifications/cancelled">>,
        #{<<"requestId">> => 2}
    ),
    erlmcp_server_session:send_message(Server, CancelNotification),
    timer:sleep(100),
    ?assert(is_process_alive(Server)),
    gen_statem:stop(Server).

version_negotiation_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test-server">>,
        version => <<"1.0">>,
        capabilities => #{}
    }),
    BadVersionInit = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"1999-01-01">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, BadVersionInit),
    timer:sleep(50),
    ?assertEqual(uninitialized, gen_statem:call(Server, get_state)),
    gen_statem:stop(Server).
