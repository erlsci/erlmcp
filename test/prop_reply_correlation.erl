-module(prop_reply_correlation).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

%% PropEr property: N requests with distinct responders each get their own
%% response delivered to the correct pid. Guards the per-request reply-target
%% invariant under concurrency.

reply_correlation_test() ->
    ?assert(proper:quickcheck(prop_reply_correlation(),
                              [quiet, {numtests, 50}, {max_size, 10}])).

prop_reply_correlation() ->
    ?FORALL(N, range(2, 8),
        begin
            {ok, Server} = erlmcp_server:start_link(#{
                name => <<"prop-server">>, version => <<"1.0">>,
                tools => [#{name => <<"echo">>, description => <<"echo">>,
                            handler => fun(Args, _Ctx) ->
                                timer:sleep(rand:uniform(10)),
                                {ok, [#{<<"type">> => <<"text">>,
                                        <<"text">> => maps:get(<<"v">>, Args, <<>>)}]}
                            end}]
            }),
            Parent = self(),
            Sink = spawn(fun() -> sink() end),
            Receivers = [spawn(fun() -> recv_loop(Parent, I) end)
                         || I <- lists:seq(1, N)],
            Responders = [erlmcp_reply:new_device(R) || R <- Receivers],
            PushR = erlmcp_reply:new_device(Sink),
            {ok, Session} = erlmcp_server_session:start_link(
                #{server => Server, responder => PushR}),
            InitMsg = erlmcp_json_rpc:encode_request(1, <<"initialize">>,
                #{<<"protocolVersion">> => <<"2025-11-25">>,
                  <<"capabilities">> => #{}}),
            ok = erlmcp_server_session:send_message(Session, InitMsg),
            timer:sleep(30),
            flush_mailbox(),
            lists:foreach(fun({I, Resp}) ->
                Val = integer_to_binary(I),
                Req = erlmcp_json_rpc:encode_request(
                    I + 100, <<"tools/call">>,
                    #{<<"name">> => <<"echo">>,
                      <<"arguments">> => #{<<"v">> => Val}}),
                ok = erlmcp_server_session:send_message(Session, Req, Resp)
            end, lists:zip(lists:seq(1, N), Responders)),
            Results = collect_results(N, 3000),
            catch gen_statem:stop(Session),
            catch gen_server:stop(Server),
            lists:foreach(fun(R) -> exit(R, kill) end, Receivers),
            exit(Sink, kill),
            check_correlation(N, Results)
        end).

flush_mailbox() ->
    receive _ -> flush_mailbox() after 0 -> ok end.

recv_loop(Parent, Id) ->
    receive
        {send, Json} ->
            Parent ! {reply_received, Id, Json},
            recv_loop(Parent, Id)
    after 5000 ->
        ok
    end.

sink() ->
    receive _ -> sink() after 5000 -> ok end.

collect_results(N, Timeout) ->
    collect_results(N, Timeout, []).

collect_results(0, _Timeout, Acc) ->
    Acc;
collect_results(N, Timeout, Acc) ->
    receive
        {reply_received, Id, Json} ->
            collect_results(N - 1, Timeout, [{Id, Json} | Acc])
    after Timeout ->
        Acc
    end.

check_correlation(N, Results) ->
    length(Results) =:= N andalso
    lists:all(fun({RecvId, Json}) ->
        case erlmcp_codec:decode(Json) of
            {ok, #{<<"id">> := ReqId, <<"result">> := #{<<"content">> := [#{<<"text">> := Val}]}}} ->
                ExpectedId = RecvId + 100,
                ExpectedVal = integer_to_binary(RecvId),
                ReqId =:= ExpectedId andalso Val =:= ExpectedVal;
            _ ->
                false
        end
    end, Results).
