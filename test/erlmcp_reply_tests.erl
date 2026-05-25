-module(erlmcp_reply_tests).

-include_lib("eunit/include/eunit.hrl").

device_responder_delivers_test() ->
    Responder = erlmcp_reply:new_device(self()),
    Json = <<"[\"hello\"]">>,
    ok = erlmcp_reply:send(Responder, Json),
    receive
        {send, Received} -> ?assertEqual(Json, Received)
    after 1000 ->
        ?assert(false)
    end.

device_responder_to_another_pid_test() ->
    Parent = self(),
    Receiver = spawn_link(fun() ->
        receive
            {send, Data} -> Parent ! {got, Data}
        end
    end),
    Responder = erlmcp_reply:new_device(Receiver),
    ok = erlmcp_reply:send(Responder, <<"test">>),
    receive
        {got, <<"test">>} -> ok
    after 1000 ->
        ?assert(false)
    end.

multiple_sends_test() ->
    Responder = erlmcp_reply:new_device(self()),
    ok = erlmcp_reply:send(Responder, <<"one">>),
    ok = erlmcp_reply:send(Responder, <<"two">>),
    ok = erlmcp_reply:send(Responder, <<"three">>),
    receive {send, <<"one">>} -> ok after 100 -> ?assert(false) end,
    receive {send, <<"two">>} -> ok after 100 -> ?assert(false) end,
    receive {send, <<"three">>} -> ok after 100 -> ?assert(false) end.
