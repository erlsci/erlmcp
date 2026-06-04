-module(erlmcp_http_session_mgr_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    {ok, ServerPid} = erlmcp_server:start_link(#{
        name => <<"test">>,
        version => <<"0.1.0">>
    }),
    {ok, MgrPid} = erlmcp_http_session_mgr:start_link(#{
        server_pid => ServerPid,
        idle_timeout => 60000,
        server_name => <<"test">>,
        server_version => <<"0.1.0">>
    }),
    {ServerPid, MgrPid}.

cleanup({ServerPid, MgrPid}) ->
    catch gen_server:stop(MgrPid),
    catch gen_server:stop(ServerPid),
    ok.

session_mgr_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        fun mint_returns_id_and_pid/1,
        fun session_id_is_binary/1,
        fun lookup_known_session/1,
        fun lookup_unknown_session/1,
        fun evict_removes_session/1,
        fun auto_evict_on_death/1,
        fun distinct_ids_per_mint/1,
        fun set_and_clear_push_target/1
    ]}.

mint_returns_id_and_pid({_ServerPid, MgrPid}) ->
    fun() ->
        {ok, SessionId, SessionPid} = erlmcp_http_session_mgr:mint(MgrPid),
        ?assert(is_binary(SessionId)),
        ?assert(is_pid(SessionPid)),
        ?assert(is_process_alive(SessionPid))
    end.

session_id_is_binary({_ServerPid, MgrPid}) ->
    fun() ->
        {ok, SessionId, _} = erlmcp_http_session_mgr:mint(MgrPid),
        ?assert(is_binary(SessionId)),
        ?assertEqual(32, byte_size(SessionId))
    end.

lookup_known_session({_ServerPid, MgrPid}) ->
    fun() ->
        {ok, SessionId, SessionPid} = erlmcp_http_session_mgr:mint(MgrPid),
        ?assertEqual({ok, SessionPid}, erlmcp_http_session_mgr:lookup(MgrPid, SessionId))
    end.

lookup_unknown_session({_ServerPid, MgrPid}) ->
    fun() ->
        ?assertEqual({error, not_found},
                     erlmcp_http_session_mgr:lookup(MgrPid, <<"nonexistent">>))
    end.

evict_removes_session({_ServerPid, MgrPid}) ->
    fun() ->
        {ok, SessionId, _SessionPid} = erlmcp_http_session_mgr:mint(MgrPid),
        ok = erlmcp_http_session_mgr:evict(MgrPid, SessionId),
        ?assertEqual({error, not_found},
                     erlmcp_http_session_mgr:lookup(MgrPid, SessionId))
    end.

auto_evict_on_death({_ServerPid, MgrPid}) ->
    fun() ->
        {ok, SessionId, SessionPid} = erlmcp_http_session_mgr:mint(MgrPid),
        gen_statem:stop(SessionPid),
        timer:sleep(50),
        ?assertEqual({error, not_found},
                     erlmcp_http_session_mgr:lookup(MgrPid, SessionId))
    end.

distinct_ids_per_mint({_ServerPid, MgrPid}) ->
    fun() ->
        {ok, Id1, _} = erlmcp_http_session_mgr:mint(MgrPid),
        {ok, Id2, _} = erlmcp_http_session_mgr:mint(MgrPid),
        {ok, Id3, _} = erlmcp_http_session_mgr:mint(MgrPid),
        ?assertNotEqual(Id1, Id2),
        ?assertNotEqual(Id2, Id3),
        ?assertNotEqual(Id1, Id3)
    end.

set_and_clear_push_target({_ServerPid, MgrPid}) ->
    fun() ->
        {ok, SessionId, _} = erlmcp_http_session_mgr:mint(MgrPid),
        ok = erlmcp_http_session_mgr:set_push_target(MgrPid, SessionId, self()),
        ok = erlmcp_http_session_mgr:clear_push_target(MgrPid, SessionId)
    end.

push_relay_delivers_to_sse_target_test() ->
    {ok, ServerPid} = erlmcp_server:start_link(#{
        name => <<"relay-test">>,
        version => <<"0.1.0">>
    }),
    {ok, MgrPid} = erlmcp_http_session_mgr:start_link(#{
        server_pid => ServerPid,
        idle_timeout => 60000,
        server_name => <<"relay-test">>,
        server_version => <<"0.1.0">>
    }),
    {ok, SessionId, SessionPid} = erlmcp_http_session_mgr:mint(MgrPid),
    ok = erlmcp_http_session_mgr:set_push_target(MgrPid, SessionId, self()),
    Responder = get_session_responder(SessionPid),
    erlmcp_reply:send(Responder, <<"push_event_data">>),
    receive
        {sse_event, <<"push_event_data">>} -> ok
    after 1000 ->
        error(push_relay_timeout)
    end,
    gen_server:stop(MgrPid),
    gen_server:stop(ServerPid).

push_relay_no_target_does_not_crash_test() ->
    {ok, ServerPid} = erlmcp_server:start_link(#{
        name => <<"notarget">>,
        version => <<"0.1.0">>
    }),
    {ok, MgrPid} = erlmcp_http_session_mgr:start_link(#{
        server_pid => ServerPid,
        idle_timeout => 60000,
        server_name => <<"notarget">>,
        server_version => <<"0.1.0">>
    }),
    {ok, SessionId, SessionPid} = erlmcp_http_session_mgr:mint(MgrPid),
    Responder = get_session_responder(SessionPid),
    erlmcp_reply:send(Responder, <<"no_target">>),
    timer:sleep(50),
    ?assertMatch({ok, _}, erlmcp_http_session_mgr:lookup(MgrPid, SessionId)),
    gen_server:stop(MgrPid),
    gen_server:stop(ServerPid).

unknown_call_test() ->
    {ok, ServerPid} = erlmcp_server:start_link(#{
        name => <<"unknown">>,
        version => <<"0.1.0">>
    }),
    {ok, MgrPid} = erlmcp_http_session_mgr:start_link(#{
        server_pid => ServerPid,
        idle_timeout => 60000,
        server_name => <<"unknown">>,
        server_version => <<"0.1.0">>
    }),
    ?assertEqual({error, unknown_request}, gen_server:call(MgrPid, foo)),
    MgrPid ! unexpected_message,
    gen_server:cast(MgrPid, unexpected_cast),
    timer:sleep(50),
    ?assert(is_process_alive(MgrPid)),
    gen_server:stop(MgrPid),
    gen_server:stop(ServerPid).

set_push_target_unknown_session_test() ->
    {ok, ServerPid} = erlmcp_server:start_link(#{
        name => <<"unknown_push">>,
        version => <<"0.1.0">>
    }),
    {ok, MgrPid} = erlmcp_http_session_mgr:start_link(#{
        server_pid => ServerPid,
        idle_timeout => 60000,
        server_name => <<"unknown_push">>,
        server_version => <<"0.1.0">>
    }),
    ok = erlmcp_http_session_mgr:set_push_target(MgrPid, <<"nope">>, self()),
    ok = erlmcp_http_session_mgr:clear_push_target(MgrPid, <<"nope">>),
    gen_server:stop(MgrPid),
    gen_server:stop(ServerPid).

evict_unknown_session_test() ->
    {ok, ServerPid} = erlmcp_server:start_link(#{
        name => <<"evict_unknown">>,
        version => <<"0.1.0">>
    }),
    {ok, MgrPid} = erlmcp_http_session_mgr:start_link(#{
        server_pid => ServerPid,
        idle_timeout => 60000,
        server_name => <<"evict_unknown">>,
        server_version => <<"0.1.0">>
    }),
    ok = erlmcp_http_session_mgr:evict(MgrPid, <<"nonexistent">>),
    gen_server:stop(MgrPid),
    gen_server:stop(ServerPid).

listener_ref_without_listener_test() ->
    {ok, ServerPid} = erlmcp_server:start_link(#{
        name => <<"nolistener">>,
        version => <<"0.1.0">>
    }),
    {ok, MgrPid} = erlmcp_http_session_mgr:start_link(#{
        server_pid => ServerPid,
        idle_timeout => 60000,
        server_name => <<"nolistener">>,
        server_version => <<"0.1.0">>
    }),
    ?assertEqual(undefined, erlmcp_http_session_mgr:listener_ref(MgrPid)),
    ?assertEqual({error, no_listener}, erlmcp_http_session_mgr:get_port(MgrPid)),
    gen_server:stop(MgrPid),
    gen_server:stop(ServerPid).

get_session_responder(SessionPid) ->
    {dictionary, Dict} = process_info(SessionPid, dictionary),
    case proplists:get_value('$initial_call', Dict) of
        _ ->
            sys:get_state(SessionPid, 1000)
    end,
    {_, Data} = sys:get_state(SessionPid),
    element(4, Data).

idle_gc_test() ->
    {ok, ServerPid} = erlmcp_server:start_link(#{
        name => <<"gc-test">>,
        version => <<"0.1.0">>
    }),
    {ok, MgrPid} = erlmcp_http_session_mgr:start_link(#{
        server_pid => ServerPid,
        idle_timeout => 200,
        server_name => <<"gc-test">>,
        server_version => <<"0.1.0">>
    }),
    {ok, SessionId, _SessionPid} = erlmcp_http_session_mgr:mint(MgrPid),
    ?assertMatch({ok, _}, erlmcp_http_session_mgr:lookup(MgrPid, SessionId)),
    timer:sleep(500),
    ?assertEqual({error, not_found},
                 erlmcp_http_session_mgr:lookup(MgrPid, SessionId)),
    gen_server:stop(MgrPid),
    gen_server:stop(ServerPid).
