-module(erlmcp_stdio_race_SUITE).

%% P6M2-6: Race conformance — register N tools + M resources + K prompts
%% via config, drive initialize then tools/list / resources/list / prompts/list
%% — each list returns ALL registered items on the first request.

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, race_conformance/1]).

all() -> [race_conformance].

race_conformance(_Config) ->
    N = 7, M = 3, K = 2,
    Tools = [#{name => iolist_to_binary(["tool_", integer_to_list(I)]),
               description => <<"test tool">>,
               handler => fun(_, _) -> {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"ok">>}]} end}
             || I <- lists:seq(1, N)],
    Resources = [#{uri => iolist_to_binary(["res://", integer_to_list(I)]),
                   name => <<"test resource">>,
                   handler => fun(_) -> {ok, #{<<"uri">> => <<"res://1">>, <<"text">> => <<"x">>}} end}
                 || I <- lists:seq(1, M)],
    Prompts = [#{name => iolist_to_binary(["prompt_", integer_to_list(I)]),
                 description => <<"test prompt">>,
                 handler => fun(_, _) -> {ok, []} end}
               || I <- lists:seq(1, K)],

    %% Config-driven: everything registered before serve
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"race-test">>, version => <<"1.0">>,
        tools => Tools, resources => Resources, prompts => Prompts
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, S} = erlmcp_server_session:start_link(#{
        server => Srv, responder => R,
        name => <<"race-test">>, version => <<"1.0">>
    }),

    %% Initialize
    send(S, 1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    _ = receive_json(),

    %% tools/list — must return all N
    send(S, 2, <<"tools/list">>, #{}),
    ?assertEqual(N, length(maps:get(<<"tools">>, receive_result()))),

    %% resources/list — must return all M
    send(S, 3, <<"resources/list">>, #{}),
    ?assertEqual(M, length(maps:get(<<"resources">>, receive_result()))),

    %% prompts/list — must return all K
    send(S, 4, <<"prompts/list">>, #{}),
    ?assertEqual(K, length(maps:get(<<"prompts">>, receive_result()))),

    gen_statem:stop(S),
    gen_server:stop(Srv).

send(S, Id, Method, Params) ->
    Req = erlmcp_json_rpc:encode_request(Id, Method, Params),
    erlmcp_server_session:send_message(S, Req).

receive_json() ->
    receive {send, Json} -> {ok, D} = erlmcp_codec:decode(Json), D
    after 2000 -> error(timeout) end.

receive_result() ->
    maps:get(<<"result">>, receive_json()).
