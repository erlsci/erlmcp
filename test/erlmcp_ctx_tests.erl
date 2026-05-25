-module(erlmcp_ctx_tests).

-include_lib("eunit/include/eunit.hrl").

new_and_accessors_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), request_id => 42}),
    ?assertEqual(self(), erlmcp_ctx:session(Ctx)),
    ?assertEqual(42, erlmcp_ctx:request_id(Ctx)),
    ?assertEqual(undefined, erlmcp_ctx:progress_token(Ctx)),
    ?assertEqual(#{}, erlmcp_ctx:meta(Ctx)),
    ?assertEqual(undefined, erlmcp_ctx:server_ref(Ctx)).

server_ref_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), request_id => 1, server_ref => some_tab}),
    ?assertEqual(some_tab, erlmcp_ctx:server_ref(Ctx)).

report_progress_no_token_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), request_id => 1}),
    ?assertEqual(ok, erlmcp_ctx:report_progress(Ctx, 0.5, <<"halfway">>)),
    receive _ -> ?assert(false) after 50 -> ok end.

report_progress_with_token_test() ->
    Ctx0 = erlmcp_ctx:new(#{session => self(), request_id => 1}),
    Ctx = Ctx0#{progress_token => <<"tok-1">>},
    ?assertEqual(ok, erlmcp_ctx:report_progress(Ctx, 0.75, <<"almost">>)),
    receive
        {send_notification, 1, NotifJson} ->
            {ok, Decoded} = erlmcp_codec:decode(NotifJson),
            ?assertEqual(<<"notifications/progress">>, maps:get(<<"method">>, Decoded)),
            Params = maps:get(<<"params">>, Decoded),
            ?assertEqual(<<"tok-1">>, maps:get(<<"progressToken">>, Params)),
            ?assertEqual(0.75, maps:get(<<"progress">>, Params))
    after 2000 ->
        ?assert(false)
    end.

request_peer_timeout_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), request_id => 1, peer_timeout => 50}),
    Result = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>, #{}),
    ?assertEqual({error, timeout}, Result).

request_peer_success_test() ->
    Parent = self(),
    SessionPid = spawn_link(fun() ->
        receive
            {peer_request, Caller, CallerRef, _Method, _Params} ->
                Caller ! {peer_response, CallerRef, {ok, #{<<"done">> => true}}}
        end,
        Parent ! session_done
    end),
    Ctx = erlmcp_ctx:new(#{session => SessionPid, request_id => 1, peer_timeout => 2000}),
    Result = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>, #{<<"prompt">> => <<"hi">>}),
    ?assertEqual({ok, #{<<"done">> => true}}, Result),
    receive session_done -> ok after 1000 -> ok end.

meta_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), request_id => 1, meta => #{<<"k">> => <<"v">>}}),
    ?assertEqual(#{<<"k">> => <<"v">>}, erlmcp_ctx:meta(Ctx)).

peer_timeout_custom_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), request_id => 1, peer_timeout => 5000}),
    ?assertEqual(5000, erlmcp_ctx:peer_timeout(Ctx)).

peer_timeout_default_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), request_id => 1}),
    ?assertEqual(30000, erlmcp_ctx:peer_timeout(Ctx)).
