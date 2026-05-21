-module(erlmcp_ctx_tests).

-include_lib("eunit/include/eunit.hrl").

new_and_accessors_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), transport => self(), request_id => 42}),
    ?assertEqual(self(), erlmcp_ctx:session(Ctx)),
    ?assertEqual(self(), erlmcp_ctx:transport(Ctx)),
    ?assertEqual(42, erlmcp_ctx:request_id(Ctx)),
    ?assertEqual(undefined, erlmcp_ctx:progress_token(Ctx)),
    ?assertEqual(#{}, erlmcp_ctx:meta(Ctx)).

no_transport_test() ->
    Ctx = erlmcp_ctx:new(#{session => self(), request_id => 1}),
    ?assertEqual(undefined, erlmcp_ctx:transport(Ctx)).

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
