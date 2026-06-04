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

http_responder_delivers_test() ->
    Ref = make_ref(),
    Responder = erlmcp_reply:new_http(self(), Ref),
    Json = <<"{\"id\":1}">>,
    ok = erlmcp_reply:send(Responder, Json),
    receive
        {jsonrpc_out, RecvRef, Received} ->
            ?assertEqual(Ref, RecvRef),
            ?assertEqual(Json, Received)
    after 1000 ->
        ?assert(false)
    end.

http_responder_to_another_pid_test() ->
    Parent = self(),
    Ref = make_ref(),
    Receiver = spawn_link(fun() ->
        receive
            {jsonrpc_out, R, Data} -> Parent ! {got, R, Data}
        end
    end),
    Responder = erlmcp_reply:new_http(Receiver, Ref),
    ok = erlmcp_reply:send(Responder, <<"test">>),
    receive
        {got, Ref, <<"test">>} -> ok
    after 1000 ->
        ?assert(false)
    end.

http_ref_correlation_test() ->
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    R1 = erlmcp_reply:new_http(self(), Ref1),
    R2 = erlmcp_reply:new_http(self(), Ref2),
    ok = erlmcp_reply:send(R1, <<"first">>),
    ok = erlmcp_reply:send(R2, <<"second">>),
    receive
        {jsonrpc_out, Ref1, <<"first">>} -> ok
    after 100 ->
        ?assert(false)
    end,
    receive
        {jsonrpc_out, Ref2, <<"second">>} -> ok
    after 100 ->
        ?assert(false)
    end.

sse_responder_delivers_test() ->
    Responder = erlmcp_reply:new_sse(self()),
    Json = <<"{\"method\":\"notify\"}">>,
    ok = erlmcp_reply:send(Responder, Json),
    receive
        {sse_event, Received} -> ?assertEqual(Json, Received)
    after 1000 ->
        ?assert(false)
    end.

sse_responder_to_another_pid_test() ->
    Parent = self(),
    Receiver = spawn_link(fun() ->
        receive
            {sse_event, Data} -> Parent ! {got, Data}
        end
    end),
    Responder = erlmcp_reply:new_sse(Receiver),
    ok = erlmcp_reply:send(Responder, <<"event">>),
    receive
        {got, <<"event">>} -> ok
    after 1000 ->
        ?assert(false)
    end.

sse_multiple_sends_test() ->
    Responder = erlmcp_reply:new_sse(self()),
    ok = erlmcp_reply:send(Responder, <<"a">>),
    ok = erlmcp_reply:send(Responder, <<"b">>),
    receive {sse_event, <<"a">>} -> ok after 100 -> ?assert(false) end,
    receive {sse_event, <<"b">>} -> ok after 100 -> ?assert(false) end.
