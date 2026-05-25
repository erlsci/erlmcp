-module(erlmcp_e2e_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([initialize_test/1, ping_test/1, cancel_test/1,
         initialize_ping_cancel_sequence/1]).

%%====================================================================
%% CT callbacks
%%====================================================================

all() ->
    [initialize_test, ping_test, cancel_test,
     initialize_ping_cancel_sequence].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Self = self(),
    ServerTransport = spawn_link(fun() -> transport(Self) end),
    ClientTransport = spawn_link(fun() -> transport(Self) end),
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"ct-server">>,
        version => <<"1.0">>,
        capabilities => #{<<"tools">> => #{}},
        handlers => #{<<"slow">> => fun slow_handler/2}
    }),
    Responder = erlmcp_reply:new_device(ServerTransport),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"ct-server">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => ClientTransport
    }),
    [{server, Server}, {srv, Srv}, {client, Client},
     {server_transport, ServerTransport},
     {client_transport, ClientTransport} | Config].

end_per_testcase(_TestCase, Config) ->
    Server = ?config(server, Config),
    Srv = ?config(srv, Config),
    Client = ?config(client, Config),
    catch gen_statem:stop(Client),
    catch gen_statem:stop(Server),
    catch gen_server:stop(Srv),
    ok.

%%====================================================================
%% Test cases
%%====================================================================

initialize_test(Config) ->
    Client = ?config(client, Config),
    Server = ?config(server, Config),
    do_initialize(Client, Server),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    ?assertEqual(operational, gen_statem:call(Client, get_state)).

ping_test(Config) ->
    Client = ?config(client, Config),
    Server = ?config(server, Config),
    do_initialize(Client, Server),
    do_ping(Client, Server).

cancel_test(Config) ->
    Client = ?config(client, Config),
    Server = ?config(server, Config),
    do_initialize(Client, Server),
    SlowReq = erlmcp_json_rpc:encode_request(10, <<"slow">>, #{}),
    forward_to_session(Server, SlowReq),
    timer:sleep(50),
    erlmcp_client_session:cancel(Client, 10),
    CancelData = wait_sent(),
    forward_to_session(Server, CancelData),
    timer:sleep(100),
    ?assert(is_process_alive(Server)).

initialize_ping_cancel_sequence(Config) ->
    Client = ?config(client, Config),
    Server = ?config(server, Config),
    do_initialize(Client, Server),
    do_ping(Client, Server),
    SlowReq = erlmcp_json_rpc:encode_request(20, <<"slow">>, #{}),
    forward_to_session(Server, SlowReq),
    timer:sleep(50),
    erlmcp_client_session:cancel(Client, 20),
    CancelData = wait_sent(),
    forward_to_session(Server, CancelData),
    timer:sleep(100),
    ?assert(is_process_alive(Server)),
    ?assert(is_process_alive(Client)),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    ?assertEqual(operational, gen_statem:call(Client, get_state)).

%%====================================================================
%% Internal — bridge client and server via message forwarding
%%====================================================================

do_initialize(Client, Server) ->
    Caller = self(),
    spawn_link(fun() ->
        Result = erlmcp_client_session:initialize(Client, #{}),
        Caller ! {init_result, Result}
    end),
    InitReq = wait_sent(),
    forward_to_session(Server, InitReq),
    InitResp = wait_sent(),
    gen_statem:cast(Client, {transport_data, InitResp}),
    _InitializedNotif = wait_sent(),
    receive {init_result, {ok, _}} -> ok
    after 5000 -> ct:fail(initialize_timeout)
    end.

do_ping(Client, Server) ->
    Caller = self(),
    spawn_link(fun() ->
        Result = erlmcp_client_session:ping(Client),
        Caller ! {ping_result, Result}
    end),
    PingReq = wait_sent(),
    forward_to_session(Server, PingReq),
    PingResp = wait_sent(),
    gen_statem:cast(Client, {transport_data, PingResp}),
    receive {ping_result, ok} -> ok
    after 5000 -> ct:fail(ping_timeout)
    end.

forward_to_session(Session, Data) ->
    erlmcp_server_session:send_message(Session, Data).

transport(Owner) ->
    receive
        {send, Data} ->
            Owner ! {transport_sent, Data},
            transport(Owner);
        _ ->
            transport(Owner)
    end.

wait_sent() ->
    receive
        {transport_sent, Data} -> Data
    after 5000 -> error(wait_sent_timeout)
    end.

slow_handler(_Params, _Ctx) ->
    receive after 30000 -> {ok, #{}} end.
