-module(erlmcp_json_rpc_tests).

-include_lib("eunit/include/eunit.hrl").

encode_request_test() ->
    Json = erlmcp_json_rpc:encode_request(1, <<"test_method">>, #{<<"param">> => <<"value">>}),
    {ok, Decoded} = erlmcp_codec:decode(Json),
    ?assertEqual(1, maps:get(<<"id">>, Decoded)),
    ?assertEqual(<<"test_method">>, maps:get(<<"method">>, Decoded)),
    ?assertEqual(<<"2.0">>, maps:get(<<"jsonrpc">>, Decoded)).

encode_response_test() ->
    Json = erlmcp_json_rpc:encode_response(1, #{<<"result">> => <<"success">>}),
    {ok, Decoded} = erlmcp_codec:decode(Json),
    ?assertEqual(1, maps:get(<<"id">>, Decoded)),
    ?assertMatch(#{<<"result">> := <<"success">>}, maps:get(<<"result">>, Decoded)).

encode_error_response_test() ->
    Json = erlmcp_json_rpc:encode_error_response(1, -32602, <<"Invalid params">>),
    {ok, Decoded} = erlmcp_codec:decode(Json),
    ?assertEqual(1, maps:get(<<"id">>, Decoded)),
    Error = maps:get(<<"error">>, Decoded),
    ?assertEqual(-32602, maps:get(<<"code">>, Error)).

decode_request_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test_method\",\"params\":{\"param\":\"value\"}}">>,
    ?assertMatch({ok, {request, 1, <<"test_method">>, _}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_response_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"success\":true}}">>,
    ?assertMatch({ok, {response, 1, #{<<"success">> := true}}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_notification_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"method\":\"notification\",\"params\":{\"data\":\"test\"}}">>,
    ?assertMatch({ok, {notification, <<"notification">>, _}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_invalid_json_test() ->
    ?assertMatch({error, _}, erlmcp_json_rpc:decode_and_classify(<<"{invalid json}">>)).

decode_non_object_test() ->
    ?assertMatch({error, {invalid_json, not_object}},
                 erlmcp_json_rpc:decode_message(<<"[1,2,3]">>)).

encode_notification_test() ->
    Json = erlmcp_json_rpc:encode_notification(<<"notifications/progress">>,
               #{<<"progress">> => 0.5}),
    {ok, Decoded} = erlmcp_codec:decode(Json),
    ?assertEqual(<<"notifications/progress">>, maps:get(<<"method">>, Decoded)),
    ?assertNot(maps:is_key(<<"id">>, Decoded)).

encode_notification_no_params_test() ->
    Json = erlmcp_json_rpc:encode_notification(<<"notifications/initialized">>, undefined),
    {ok, Decoded} = erlmcp_codec:decode(Json),
    ?assertNot(maps:is_key(<<"params">>, Decoded)).

encode_request_null_id_test() ->
    Json = erlmcp_json_rpc:encode_request(null, <<"ping">>, #{}),
    {ok, Decoded} = erlmcp_codec:decode(Json),
    ?assertEqual(null, maps:get(<<"id">>, Decoded)).

encode_request_string_id_test() ->
    Json = erlmcp_json_rpc:encode_request(<<"abc">>, <<"ping">>, #{}),
    {ok, Decoded} = erlmcp_codec:decode(Json),
    ?assertEqual(<<"abc">>, maps:get(<<"id">>, Decoded)).

decode_wrong_version_test() ->
    Json = <<"{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"ping\"}">>,
    ?assertMatch({error, {invalid_request, {wrong_version, _}}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_missing_jsonrpc_test() ->
    Json = <<"{\"id\":1,\"method\":\"ping\"}">>,
    ?assertMatch({error, {invalid_request, missing_jsonrpc}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_unknown_message_type_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"unknown\":true}">>,
    ?assertMatch({error, {invalid_request, unknown_message_type}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_invalid_method_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":123}">>,
    ?assertMatch({error, {invalid_request, {invalid_method, 123}}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_notification_invalid_method_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"method\":42}">>,
    ?assertMatch({error, {invalid_request, {invalid_method, 42}}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_request_with_list_params_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test\",\"params\":[1,2]}">>,
    ?assertMatch({ok, {request, 1, <<"test">>, [1, 2]}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_request_with_invalid_params_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test\",\"params\":\"bad\"}">>,
    ?assertMatch({ok, {request, 1, <<"test">>, undefined}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_string_id_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"result\":true}">>,
    ?assertMatch({ok, {response, <<"abc">>, true}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_null_id_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":true}">>,
    ?assertMatch({ok, {response, null, true}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_float_id_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":3.14,\"result\":true}">>,
    ?assertMatch({ok, {response, 3.14, true}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_error_response_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32600,\"message\":\"Invalid\"}}">>,
    ?assertMatch({ok, {error_response, 1, #{<<"code">> := -32600}}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_and_classify_request_test() ->
    Json = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
    ?assertMatch({ok, {request, 1, <<"ping">>, #{}}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_and_classify_response_test() ->
    Json = erlmcp_json_rpc:encode_response(1, #{<<"ok">> => true}),
    ?assertMatch({ok, {response, 1, _}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_and_classify_error_response_test() ->
    Json = erlmcp_json_rpc:encode_error_response(1, -32600, <<"Invalid">>),
    ?assertMatch({ok, {error_response, 1, _}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_and_classify_notification_test() ->
    Json = erlmcp_json_rpc:encode_notification(<<"initialized">>, #{}),
    ?assertMatch({ok, {notification, <<"initialized">>, _}},
                 erlmcp_json_rpc:decode_and_classify(Json)).

decode_and_classify_error_test() ->
    ?assertMatch({error, _},
                 erlmcp_json_rpc:decode_and_classify(<<"not json">>)).

%% Batch tests

batch_encode_test() ->
    Req = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
    Notif = erlmcp_json_rpc:encode_notification(<<"initialized">>, #{}),
    Batch = erlmcp_json_rpc:encode_batch([Req, Notif]),
    {ok, Decoded} = erlmcp_codec:decode(Batch),
    ?assert(is_list(Decoded)),
    ?assertEqual(2, length(Decoded)).

batch_decode_mixed_test() ->
    Req = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
    Notif = erlmcp_json_rpc:encode_notification(<<"initialized">>, #{}),
    Batch = erlmcp_json_rpc:encode_batch([Req, Notif]),
    {ok, {batch, Items}} = erlmcp_json_rpc:decode_and_classify_any(Batch),
    ?assertEqual(2, length(Items)),
    ?assertMatch({request, 1, <<"ping">>, _}, hd(Items)),
    ?assertMatch({notification, <<"initialized">>, _}, lists:last(Items)).

batch_empty_array_test() ->
    {ok, EmptyArray} = erlmcp_codec:encode([]),
    ?assertMatch({error, {invalid_request, empty_batch}},
                 erlmcp_json_rpc:decode_and_classify_any(EmptyArray)).

batch_malformed_member_test() ->
    {ok, BatchJson} = erlmcp_codec:encode([
        #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => 1, <<"method">> => <<"ping">>},
        <<"not an object">>,
        #{<<"jsonrpc">> => <<"2.0">>, <<"method">> => <<"notify">>}
    ]),
    {ok, {batch, Items}} = erlmcp_json_rpc:decode_and_classify_any(BatchJson),
    ?assertEqual(3, length(Items)),
    ?assertMatch({request, _, <<"ping">>, _}, lists:nth(1, Items)),
    ?assertMatch({parse_error, _}, lists:nth(2, Items)),
    ?assertMatch({notification, <<"notify">>, _}, lists:nth(3, Items)).

single_message_via_decode_any_test() ->
    Json = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
    ?assertMatch({ok, {request, 1, <<"ping">>, _}},
                 erlmcp_json_rpc:decode_and_classify_any(Json)).

error_codes_named_test() ->
    ?assertEqual(-32700, erlmcp_json_rpc:parse_error()),
    ?assertEqual(-32600, erlmcp_json_rpc:invalid_request()),
    ?assertEqual(-32601, erlmcp_json_rpc:method_not_found()),
    ?assertEqual(-32602, erlmcp_json_rpc:invalid_params()),
    ?assertEqual(-32603, erlmcp_json_rpc:internal_error()).
