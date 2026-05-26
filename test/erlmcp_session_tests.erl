-module(erlmcp_session_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Helpers — test server management
%%====================================================================

srv() ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>}),
    Srv.

srv_with_handlers(Handlers) when is_map(Handlers) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>,
        handlers => Handlers}),
    Srv.

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
    TestSrv = srv_with_handlers(#{<<"crash/test">> => CrashHandler}),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test-server">>,
        version => <<"1.0">>
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
    TestSrv = srv_with_handlers(#{<<"slow/test">> => SlowHandler}),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test-server">>,
        version => <<"1.0">>
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

parse_error_in_uninitialized_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test-server">>,
        version => <<"1.0">>
    }),
    erlmcp_server_session:send_message(Server, <<"not json">>),
    timer:sleep(50),
    ?assert(is_process_alive(Server)),
    gen_statem:stop(Server).

parse_error_in_operational_test() ->
    {ok, Server} = init_server(),
    erlmcp_server_session:send_message(Server, <<"not json">>),
    _ = wait_transport_send(),
    ?assert(is_process_alive(Server)),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    gen_statem:stop(Server).

ping_in_operational_test() ->
    flush_mailbox(),
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test-server">>,
        version => <<"1.0">>
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _InitResp = wait_transport_send(),
    PingReq = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    erlmcp_server_session:send_message(Server, PingReq),
    PingResp = wait_transport_send(),
    {ok, Decoded} = erlmcp_codec:decode(PingResp),
    ?assertEqual(2, maps:get(<<"id">>, Decoded)),
    ?assertMatch(#{}, maps:get(<<"result">>, Decoded)),
    gen_statem:stop(Server).

worker_success_result_test() ->
    OkHandler = fun(_Params, _Ctx) -> {ok, #{<<"answer">> => 42}} end,
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test-server">>, version => <<"1.0">>,
        handlers => #{<<"echo">> => OkHandler}
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test-server">>, version => <<"1.0">>
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _InitResp = wait_transport_send(),
    EchoReq = erlmcp_json_rpc:encode_request(2, <<"echo">>, #{}),
    erlmcp_server_session:send_message(Server, EchoReq),
    EchoResp = wait_transport_send(),
    {ok, Decoded} = erlmcp_codec:decode(EchoResp),
    ?assertEqual(2, maps:get(<<"id">>, Decoded)),
    ?assertMatch(#{<<"answer">> := 42}, maps:get(<<"result">>, Decoded)),
    gen_statem:stop(Server).

worker_error_result_test() ->
    ErrHandler = fun(_Params, _Ctx) -> {error, -32001, <<"Not found">>} end,
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test-server">>, version => <<"1.0">>,
        handlers => #{<<"fail">> => ErrHandler}
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test-server">>, version => <<"1.0">>
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _InitResp = wait_transport_send(),
    FailReq = erlmcp_json_rpc:encode_request(2, <<"fail">>, #{}),
    erlmcp_server_session:send_message(Server, FailReq),
    FailResp = wait_transport_send(),
    {ok, Decoded} = erlmcp_codec:decode(FailResp),
    ?assertEqual(2, maps:get(<<"id">>, Decoded)),
    ?assertMatch(#{<<"code">> := -32001}, maps:get(<<"error">>, Decoded)),
    gen_statem:stop(Server).

method_not_found_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test-server">>,
        version => <<"1.0">>
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _InitResp = wait_transport_send(),
    UnknownReq = erlmcp_json_rpc:encode_request(2, <<"unknown/method">>, #{}),
    erlmcp_server_session:send_message(Server, UnknownReq),
    Resp = wait_transport_send(),
    {ok, Decoded} = erlmcp_codec:decode(Resp),
    ?assertMatch(#{<<"code">> := -32601}, maps:get(<<"error">>, Decoded)),
    gen_statem:stop(Server).

notifications_initialized_ignored_test() ->
    {ok, Server} = init_server(),
    Notif = erlmcp_json_rpc:encode_notification(<<"notifications/initialized">>, #{}),
    erlmcp_server_session:send_message(Server, Notif),
    timer:sleep(50),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    gen_statem:stop(Server).

get_state_all_states_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test">>, version => <<"1.0">>
    }),
    ?assertEqual(uninitialized, gen_statem:call(Server, get_state)),
    gen_statem:stop(Server).

uninitialized_ignores_unknown_events_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test">>, version => <<"1.0">>
    }),
    gen_statem:cast(Server, some_unknown_event),
    Server ! some_info_message,
    timer:sleep(50),
    ?assert(is_process_alive(Server)),
    gen_statem:stop(Server).

cancel_nonexistent_request_test() ->
    {ok, Server} = init_server(),
    CancelNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/cancelled">>, #{<<"requestId">> => 999}),
    erlmcp_server_session:send_message(Server, CancelNotif),
    timer:sleep(50),
    ?assert(is_process_alive(Server)),
    gen_statem:stop(Server).

mfa_handler_test() ->
    Responder = erlmcp_reply:new_device(self()),
    TestSrv = srv_with_handlers(#{<<"mfa">> => {erlmcp_capabilities, supported_versions}}),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test-server">>,
        version => <<"1.0">>
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _InitResp = wait_transport_send(),
    MfaReq = erlmcp_json_rpc:encode_request(2, <<"mfa">>, #{}),
    erlmcp_server_session:send_message(Server, MfaReq),
    _ErrorResp = wait_transport_send(),
    ?assert(is_process_alive(Server)),
    gen_statem:stop(Server).

terminate_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test">>, version => <<"1.0">>
    }),
    MonRef = monitor(process, Server),
    gen_statem:stop(Server),
    receive
        {'DOWN', MonRef, process, Server, normal} -> ok
    after 2000 -> ?assert(false)
    end.

%%====================================================================
%% Tools — registration, list, call, validation (M2a)
%%====================================================================

tools_register_and_list_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"echo">>,
        description => <<"Echo tool">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    [Tool] = maps:values(erlmcp_server:get_tools(erlmcp_server:catalog_table(TestSrv))),
    ?assertEqual(<<"echo">>, maps:get(name, Tool)),
    gen_statem:stop(Server).

tools_unregister_test() ->
    TestSrv = srv(),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"t">>, description => <<"t">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    ok = erlmcp_server:unregister_tool(TestSrv, <<"t">>),
    ?assertEqual([], maps:values(erlmcp_server:get_tools(erlmcp_server:catalog_table(TestSrv)))),
    gen_server:stop(TestSrv).

tools_register_handler_module_test() ->
    TestSrv = srv(),
    ok = erlmcp_server:register_handler(TestSrv, test_calc_handler),
    Tools = maps:values(erlmcp_server:get_tools(erlmcp_server:catalog_table(TestSrv))),
    ?assert(length(Tools) > 0),
    gen_server:stop(TestSrv).

tools_call_fun_handler_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"double">>,
        description => <<"Double">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"x">>, erlmcp_schema:number(), [required])
        ]),
        handler => fun(#{<<"x">> := X}, _) ->
            {ok, erlmcp:text(integer_to_binary(trunc(X * 2)))}
        end
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"double">>,
        <<"arguments">> => #{<<"x">> => 21}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode_resp(wait_transport_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"42">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(Server).

tools_call_behaviour_handler_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_handler(TestSrv, test_calc_handler),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"add">>,
        <<"arguments">> => #{<<"a">> => 3, <<"b">> => 4}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode_resp(wait_transport_send()),
    [Content] = maps:get(<<"content">>, maps:get(<<"result">>, Resp)),
    ?assertEqual(<<"7">>, maps:get(<<"text">>, Content)),
    gen_statem:stop(Server).

tools_call_input_validation_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"strict">>,
        description => <<"Strict">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"name">>, erlmcp_schema:string(), [required])
        ]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"strict">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode_resp(wait_transport_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp),
    gen_statem:stop(Server).

tools_call_unknown_tool_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"nonexistent">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode_resp(wait_transport_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp),
    gen_statem:stop(Server).

tools_call_missing_name_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode_resp(wait_transport_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp),
    gen_statem:stop(Server).

tools_list_via_protocol_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"t1">>,
        description => <<"Tool 1">>,
        input_schema => erlmcp_schema:object([]),
        category => <<"cat_a">>,
        when_to_use => <<"When needed">>,
        annotations => #{readOnlyHint => true},
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    init_server_with_transport(Server),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq),
    Resp = decode_resp(wait_transport_send()),
    Result = maps:get(<<"result">>, Resp),
    [Tool] = maps:get(<<"tools">>, Result),
    ?assertEqual(<<"t1">>, maps:get(<<"name">>, Tool)),
    ?assertEqual(<<"Tool 1">>, maps:get(<<"description">>, Tool)),
    ?assertMatch(#{<<"readOnlyHint">> := true}, maps:get(<<"annotations">>, Tool)),
    Meta = maps:get(<<"_meta">>, Tool),
    ?assertEqual(<<"cat_a">>, maps:get(<<"io.erlmcp/category">>, Meta)),
    gen_statem:stop(Server).

tools_structured_output_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    OutSchema = erlmcp_schema:object([
        erlmcp_schema:field(<<"result">>, erlmcp_schema:number(), [required])
    ]),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"calc">>,
        description => <<"Calc">>,
        input_schema => erlmcp_schema:object([]),
        output_schema => OutSchema,
        handler => fun(_, _) -> {ok, erlmcp:text(<<"42">>), #{<<"result">> => 42}} end
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"calc">>, <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode_resp(wait_transport_send()),
    Result = maps:get(<<"result">>, Resp),
    ?assertMatch(#{<<"structuredContent">> := #{<<"result">> := 42}}, Result),
    gen_statem:stop(Server).

tools_output_validation_failure_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    OutSchema = erlmcp_schema:object([
        erlmcp_schema:field(<<"value">>, erlmcp_schema:string(), [required])
    ]),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"bad">>,
        description => <<"Bad output">>,
        input_schema => erlmcp_schema:object([]),
        output_schema => OutSchema,
        handler => fun(_, _) -> {ok, erlmcp:text(<<"x">>), #{<<"wrong">> => 1}} end
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"bad">>, <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode_resp(wait_transport_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32603}}, Resp),
    gen_statem:stop(Server).

tools_list_changed_notification_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    init_server_with_transport(Server),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"dyn">>, description => <<"Dyn">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    Notif = decode_resp(wait_transport_send()),
    ?assertEqual(<<"notifications/tools/list_changed">>,
                 maps:get(<<"method">>, Notif)),
    ok = erlmcp_server:unregister_tool(TestSrv, <<"dyn">>),
    Notif2 = decode_resp(wait_transport_send()),
    ?assertEqual(<<"notifications/tools/list_changed">>,
                 maps:get(<<"method">>, Notif2)),
    gen_statem:stop(Server).

tools_progress_notification_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"slow">>,
        description => <<"Slow">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            erlmcp_ctx:report_progress(Ctx, 0.5, <<"halfway">>),
            {ok, erlmcp:text(<<"done">>)}
        end
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"slow">>,
        <<"arguments">> => #{},
        <<"_meta">> => #{<<"progressToken">> => <<"tok">>}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    ProgressNotif = decode_resp(wait_transport_send()),
    ?assertEqual(<<"notifications/progress">>,
                 maps:get(<<"method">>, ProgressNotif)),
    Params = maps:get(<<"params">>, ProgressNotif),
    ?assertEqual(<<"tok">>, maps:get(<<"progressToken">>, Params)),
    _ToolResp = wait_transport_send(),
    gen_statem:stop(Server).

capability_tools_derived_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"t">>, description => <<"t">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    Resp = decode_resp(wait_transport_send()),
    Caps = maps:get(<<"capabilities">>, maps:get(<<"result">>, Resp)),
    ?assert(maps:is_key(<<"tools">>, Caps)),
    ?assertEqual(true, maps:get(<<"listChanged">>,
                                maps:get(<<"tools">>, Caps))),
    gen_statem:stop(Server).

instructions_generated_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_handler(TestSrv, test_calc_handler),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    Resp = decode_resp(wait_transport_send()),
    Instructions = maps:get(<<"instructions">>,
                            maps:get(<<"result">>, Resp)),
    ?assert(is_binary(Instructions)),
    ?assert(byte_size(Instructions) > 0),
    Frozen = erlmcp_server_session:get_instructions(Server),
    ?assertEqual(Instructions, Frozen),
    gen_statem:stop(Server).

tools_all_content_types_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"types">>,
        description => <<"All types">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) ->
            {ok, [
                erlmcp:text(<<"t">>),
                erlmcp:image(<<"d">>, <<"image/png">>),
                erlmcp:audio(<<"d">>, <<"audio/wav">>),
                erlmcp:embedded_resource(#{<<"uri">> => <<"f:///a">>}),
                erlmcp:resource_link(<<"f:///b">>, <<"text/plain">>)
            ]}
        end
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"types">>, <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode_resp(wait_transport_send()),
    Content = maps:get(<<"content">>, maps:get(<<"result">>, Resp)),
    ?assertEqual(5, length(Content)),
    gen_statem:stop(Server).

%%====================================================================
%% Helpers
%%====================================================================

init_server() ->
    flush_mailbox(),
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test-server">>,
        version => <<"1.0">>
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{<<"name">> => <<"test">>, <<"version">> => <<"1.0">>}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _ = wait_transport_send(),
    {ok, Server}.

%% Cover resource/prompt/logging registration + list via protocol
tools_list_with_meta_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_resource(TestSrv, #{
        uri => <<"x://a">>, name => <<"A">>,
        handler => fun(_) -> {ok, #{<<"uri">> => <<"x://a">>, <<"text">> => <<"t">>}} end
    }),
    ok = erlmcp_server:register_prompt(TestSrv, #{
        name => <<"p">>, description => <<"P">>,
        handler => fun(_, _) -> {ok, []} end
    }),
    ok = erlmcp_server_session:set_log_level(Server, info),
    init_server_with_transport(Server),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"resources/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq),
    Resp = decode_resp(wait_transport_send()),
    ?assert(maps:is_key(<<"result">>, Resp)),
    gen_statem:stop(Server).

server_logging_emit_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    init_server_with_transport(Server),
    ok = erlmcp_server_session:set_log_level(Server, debug),
    erlmcp_server_session:emit_log(Server, info, <<"test">>, <<"msg">>),
    Notif = decode_resp(wait_transport_send()),
    ?assertEqual(<<"notifications/message">>, maps:get(<<"method">>, Notif)),
    gen_statem:stop(Server).

server_resource_subscribe_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_resource(TestSrv, #{
        uri => <<"x://a">>, name => <<"A">>,
        handler => fun(_) -> {ok, #{<<"uri">> => <<"x://a">>, <<"text">> => <<"t">>}} end
    }),
    init_server_with_transport(Server),
    SubReq = erlmcp_json_rpc:encode_request(2, <<"resources/subscribe">>,
        #{<<"uri">> => <<"x://a">>}),
    erlmcp_server_session:send_message(Server, SubReq),
    _SubResp = wait_transport_send(),
    erlmcp_server_session:notify_resource_updated(Server, <<"x://a">>),
    Notif = decode_resp(wait_transport_send()),
    ?assertEqual(<<"notifications/resources/updated">>, maps:get(<<"method">>, Notif)),
    gen_statem:stop(Server).

server_completion_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_prompt(TestSrv, #{
        name => <<"p">>, description => <<"P">>,
        handler => fun(_, _) -> {ok, []} end,
        completions => #{<<"arg">> => fun(_) -> [<<"v1">>] end}
    }),
    init_server_with_transport(Server),
    CompReq = erlmcp_json_rpc:encode_request(2, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"p">>},
        <<"argument">> => #{<<"name">> => <<"arg">>, <<"value">> => <<"">>}
    }),
    erlmcp_server_session:send_message(Server, CompReq),
    Resp = decode_resp(wait_transport_send()),
    ?assert(maps:is_key(<<"result">>, Resp)),
    gen_statem:stop(Server).

%% Cover initializing/shutting_down state catch-alls
initializing_state_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    gen_statem:cast(Server, {transport_data, <<"junk">>}),
    Server ! {transport_data, <<"junk">>},
    gen_statem:cast(Server, random_event),
    Server ! random_info,
    timer:sleep(50),
    ?assert(is_process_alive(Server)),
    gen_statem:stop(Server).

%% Cover {M,F} dispatch path
mf_tool_dispatch_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_tool(TestSrv, #{
        name => <<"mf_tool">>,
        description => <<"MF dispatch">>,
        input_schema => erlmcp_schema:object([]),
        handler => {erlmcp_capabilities, supported_versions}
    }),
    init_server_with_transport(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"mf_tool">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    _Resp = wait_transport_send(),
    ?assert(is_process_alive(Server)),
    gen_statem:stop(Server).

%% Cover log levels not hit in other tests
log_levels_coverage_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    init_server_with_transport(Server),
    ok = erlmcp_server_session:set_log_level(Server, debug),
    lists:foreach(fun(Level) ->
        erlmcp_server_session:emit_log(Server, Level, <<"test">>, <<"msg">>),
        _Notif = wait_transport_send()
    end, [debug, info, notice, warning, error, critical, alert, emergency]),
    gen_statem:stop(Server),
    flush_sends().

%% Cover pagination cursor path (>50 items)
pagination_cursor_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    lists:foreach(fun(N) ->
        Name = list_to_binary("tool_" ++ integer_to_list(N)),
        ok = erlmcp_server:register_tool(TestSrv, #{
            name => Name, description => Name,
            input_schema => erlmcp_schema:object([]),
            handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
        })
    end, lists:seq(1, 55)),
    init_server_with_transport(Server),
    ListReq1 = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq1),
    Resp1 = decode_resp(wait_transport_send()),
    Result1 = maps:get(<<"result">>, Resp1),
    ?assertEqual(50, length(maps:get(<<"tools">>, Result1))),
    Cursor = maps:get(<<"nextCursor">>, Result1),
    ?assert(is_binary(Cursor)),
    ListReq2 = erlmcp_json_rpc:encode_request(3, <<"tools/list">>,
        #{<<"cursor">> => Cursor}),
    erlmcp_server_session:send_message(Server, ListReq2),
    Resp2 = decode_resp(wait_transport_send()),
    Result2 = maps:get(<<"result">>, Resp2),
    ?assertEqual(5, length(maps:get(<<"tools">>, Result2))),
    ?assertNot(maps:is_key(<<"nextCursor">>, Result2)),
    gen_statem:stop(Server).

%% Cover resource handler error path
resource_handler_error_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_resource(TestSrv, #{
        uri => <<"err://fail">>, name => <<"Fail">>,
        handler => fun(_Ctx) -> {error, -32000, <<"custom error">>} end
    }),
    init_server_with_transport(Server),
    ReadReq = erlmcp_json_rpc:encode_request(2, <<"resources/read">>,
        #{<<"uri">> => <<"err://fail">>}),
    erlmcp_server_session:send_message(Server, ReadReq),
    Resp = decode_resp(wait_transport_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32000}}, Resp),
    gen_statem:stop(Server).

%% Cover template match failure paths
template_match_failure_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_resource_template(TestSrv, #{
        uri_template => <<"t://a/{id}/b">>, name => <<"T">>,
        handler => fun(_, _) -> {ok, #{<<"uri">> => <<"t://x">>, <<"text">> => <<"y">>}} end
    }),
    init_server_with_transport(Server),
    ReadReq = erlmcp_json_rpc:encode_request(2, <<"resources/read">>,
        #{<<"uri">> => <<"t://a/1/b/extra">>}),
    erlmcp_server_session:send_message(Server, ReadReq),
    Resp = decode_resp(wait_transport_send()),
    ?assertMatch(#{<<"error">> := _}, Resp),
    gen_statem:stop(Server).

%% Cover completion for missing prompt/template
completion_missing_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    init_server_with_transport(Server),
    CompReq = erlmcp_json_rpc:encode_request(2, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"missing">>},
        <<"argument">> => #{<<"name">> => <<"x">>, <<"value">> => <<"">>}
    }),
    erlmcp_server_session:send_message(Server, CompReq),
    Resp = decode_resp(wait_transport_send()),
    Result = maps:get(<<"result">>, Resp),
    ?assertEqual([], maps:get(<<"values">>, maps:get(<<"completion">>, Result))),
    gen_statem:stop(Server).

%% Cover unknown common_call in shutting_down
shutting_down_call_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ?assertEqual({error, unknown_request}, gen_statem:call(Server, bogus)),
    gen_statem:stop(Server).

%% Cover inbound via info (not cast) — the M4 transport path
inbound_via_info_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    Server ! {transport_data, InitReq},
    _InitResp = wait_transport_send(),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    PingReq = erlmcp_json_rpc:encode_request(2, <<"ping">>, #{}),
    Server ! {transport_data, PingReq},
    _PingResp = wait_transport_send(),
    gen_statem:stop(Server).

%% Cover resource list contents format
resource_list_contents_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_resource(TestSrv, #{
        uri => <<"r://a">>, name => <<"A">>,
        description => <<"Desc A">>, mime_type => <<"text/plain">>,
        handler => fun(_Ctx) ->
            {ok, [#{<<"uri">> => <<"r://a">>, <<"text">> => <<"multi">>},
                   #{<<"uri">> => <<"r://a">>, <<"text">> => <<"items">>}]}
        end
    }),
    init_server_with_transport(Server),
    ReadReq = erlmcp_json_rpc:encode_request(2, <<"resources/read">>,
        #{<<"uri">> => <<"r://a">>}),
    erlmcp_server_session:send_message(Server, ReadReq),
    Resp = decode_resp(wait_transport_send()),
    Contents = maps:get(<<"contents">>, maps:get(<<"result">>, Resp)),
    ?assertEqual(2, length(Contents)),
    gen_statem:stop(Server).

%% Cover prompt get error path
prompt_get_error_test() ->
    TestSrv = srv(),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => TestSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp_server:register_prompt(TestSrv, #{
        name => <<"fail_prompt">>, description => <<"Fails">>,
        handler => fun(_, _) -> {error, -32000, <<"prompt error">>} end
    }),
    init_server_with_transport(Server),
    GetReq = erlmcp_json_rpc:encode_request(2, <<"prompts/get">>,
        #{<<"name">> => <<"fail_prompt">>, <<"arguments">> => #{}}),
    erlmcp_server_session:send_message(Server, GetReq),
    Resp = decode_resp(wait_transport_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32000}}, Resp),
    gen_statem:stop(Server).

init_server_with_transport(Server) ->
    flush_sends(),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _ = wait_transport_send(),
    ok.

decode_resp(Json) ->
    {ok, Decoded} = erlmcp_codec:decode(Json),
    Decoded.

wait_transport_send() ->
    receive {send, Data} -> Data after 5000 -> error(transport_send_timeout) end.

flush_mailbox() ->
    receive _ -> flush_mailbox() after 0 -> ok end.

flush_sends() ->
    receive {send, _} -> flush_sends() after 0 -> ok end.
