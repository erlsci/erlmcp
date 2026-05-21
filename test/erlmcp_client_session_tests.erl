-module(erlmcp_client_session_tests).

-include_lib("eunit/include/eunit.hrl").

client_session_test_() ->
    {foreach,
     fun() -> drain_mailbox() end,
     fun(_) -> drain_mailbox() end,
     [fun(_) -> {"start and stop", fun start_stop/0} end,
      fun(_) -> {"initialize", fun initialize_e2e/0} end,
      fun(_) -> {"ping after init", fun ping_after_init/0} end,
      fun(_) -> {"cancel sends notification", fun cancel_sends_notification/0} end,
      fun(_) -> {"init error stays uninitialized", fun init_error/0} end,
      fun(_) -> {"junk in uninitialized is ignored", fun junk_ignored/0} end,
      fun(_) -> {"operational ignores junk", fun operational_ignores_junk/0} end,
      fun(_) -> {"operational ignores unknown events", fun operational_unknown_events/0} end]}.

start_stop() ->
    Transport = spawn_link(fun() -> sink() end),
    {ok, C} = erlmcp_client_session:start_link(#{transport => Transport}),
    ?assertEqual(uninitialized, gen_statem:call(C, get_state)),
    erlmcp_client_session:stop(C).

initialize_e2e() ->
    {C, _T} = make_client(),
    Caller = self(),
    spawn_link(fun() -> Caller ! {r, erlmcp_client_session:initialize(C, #{})} end),
    Req = wait_sent(),
    gen_statem:cast(C, {transport_data, init_response(Req)}),
    ?assertMatch({r, {ok, #{<<"protocolVersion">> := _}}}, wait_msg()),
    ?assertEqual(operational, gen_statem:call(C, get_state)),
    erlmcp_client_session:stop(C).

ping_after_init() ->
    {C, _T} = do_init(),
    Caller = self(),
    spawn_link(fun() -> Caller ! {r, erlmcp_client_session:ping(C)} end),
    Req = wait_sent(),
    {ok, D} = erlmcp_codec:decode(Req),
    gen_statem:cast(C, {transport_data,
        erlmcp_json_rpc:encode_response(maps:get(<<"id">>, D), #{})}),
    ?assertEqual({r, ok}, wait_msg()),
    erlmcp_client_session:stop(C).

cancel_sends_notification() ->
    {C, _T} = do_init(),
    erlmcp_client_session:cancel(C, 42),
    Data = wait_sent(),
    {ok, D} = erlmcp_codec:decode(Data),
    ?assertEqual(<<"notifications/cancelled">>, maps:get(<<"method">>, D)),
    erlmcp_client_session:stop(C).

init_error() ->
    {C, _T} = make_client(),
    Caller = self(),
    spawn_link(fun() -> Caller ! {r, erlmcp_client_session:initialize(C, #{})} end),
    Req = wait_sent(),
    {ok, D} = erlmcp_codec:decode(Req),
    Id = maps:get(<<"id">>, D),
    gen_statem:cast(C, {transport_data,
        erlmcp_json_rpc:encode_error_response(Id, -32602, <<"bad version">>)}),
    ?assertMatch({r, {error, _}}, wait_msg()),
    ?assertEqual(uninitialized, gen_statem:call(C, get_state)),
    erlmcp_client_session:stop(C).

junk_ignored() ->
    {C, _T} = make_client(),
    gen_statem:cast(C, {transport_data, <<"not json">>}),
    timer:sleep(50),
    ?assertEqual(uninitialized, gen_statem:call(C, get_state)),
    erlmcp_client_session:stop(C).

%%====================================================================
%% Helpers
%%====================================================================

make_client() ->
    Self = self(),
    T = spawn_link(fun() -> transport(Self) end),
    {ok, C} = erlmcp_client_session:start_link(#{transport => T}),
    {C, T}.

do_init() ->
    {C, T} = make_client(),
    Caller = self(),
    spawn_link(fun() -> Caller ! {r, erlmcp_client_session:initialize(C, #{})} end),
    Req = wait_sent(),
    gen_statem:cast(C, {transport_data, init_response(Req)}),
    _Notif = wait_sent(),
    {r, {ok, _}} = wait_msg(),
    {C, T}.

transport(Owner) ->
    receive
        {send, Data} -> Owner ! {transport_sent, Data}, transport(Owner);
        _ -> transport(Owner)
    end.

sink() -> receive _ -> sink() end.

wait_sent() ->
    receive {transport_sent, D} -> D after 5000 -> error(send_timeout) end.

wait_msg() ->
    receive {r, _} = M -> M after 5000 -> error(msg_timeout) end.

init_response(ReqJson) ->
    {ok, D} = erlmcp_codec:decode(ReqJson),
    erlmcp_json_rpc:encode_response(maps:get(<<"id">>, D), #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"serverInfo">> => #{<<"name">> => <<"t">>, <<"version">> => <<"1">>}
    }).

operational_ignores_junk() ->
    {C, _T} = do_init(),
    gen_statem:cast(C, {transport_data, <<"not json">>}),
    timer:sleep(50),
    ?assertEqual(operational, gen_statem:call(C, get_state)),
    erlmcp_client_session:stop(C).

operational_unknown_events() ->
    {C, _T} = do_init(),
    gen_statem:cast(C, totally_unknown_event),
    C ! some_random_info,
    timer:sleep(50),
    ?assert(is_process_alive(C)),
    erlmcp_client_session:stop(C).

drain_mailbox() ->
    receive _ -> drain_mailbox() after 0 -> ok end.
