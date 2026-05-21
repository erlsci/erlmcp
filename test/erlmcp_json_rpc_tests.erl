-module(erlmcp_json_rpc_tests).

-include_lib("eunit/include/eunit.hrl").

-include("erlmcp.hrl").

encode_request_test() ->
    Json =
        erlmcp_json_rpc:encode_request(1, <<"test_method">>, #{<<"param">> => <<"value">>}),
    Expected =
        <<"{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"test_method\",\"params\":{\"param\":\"value\"}}">>,
    ?assertEqual(Expected, Json).

encode_response_test() ->
    Json = erlmcp_json_rpc:encode_response(1, #{<<"result">> => <<"success">>}),
    Expected = <<"{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"result\":\"success\"}}">>,
    ?assertEqual(Expected, Json).

encode_error_response_test() ->
    Json = erlmcp_json_rpc:encode_error_response(1, -32602, <<"Invalid params">>),
    ?assertMatch(<<"{\"error\":{\"code\":-32602,\"message\":\"Invalid params\"},\"id\":1,\"jsonrpc\":\"2.0\"}">>,
                 Json).

decode_request_test() ->
    Json =
        <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test_method\",\"params\":{\"param\":\"value\"}}">>,
    {ok, Request} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_request{id = 1, method = <<"test_method">>}, Request).

decode_response_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"success\":true}}">>,
    {ok, Response} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_response{id = 1, result = #{<<"success">> := true}}, Response).

decode_notification_test() ->
    Json =
        <<"{\"jsonrpc\":\"2.0\",\"method\":\"notification\",\"params\":{\"data\":\"test\"}}">>,
    {ok, Notification} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_notification{method = <<"notification">>}, Notification).

decode_invalid_json_test() ->
    Json = <<"{invalid json}">>,
    ?assertMatch({error, {parse_error, _}}, erlmcp_json_rpc:decode_message(Json)).

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
                 erlmcp_json_rpc:decode_message(Json)).

decode_missing_jsonrpc_test() ->
    Json = <<"{\"id\":1,\"method\":\"ping\"}">>,
    ?assertMatch({error, {invalid_request, missing_jsonrpc}},
                 erlmcp_json_rpc:decode_message(Json)).

decode_unknown_message_type_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"unknown\":true}">>,
    ?assertMatch({error, {invalid_request, unknown_message_type}},
                 erlmcp_json_rpc:decode_message(Json)).

decode_invalid_method_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":123}">>,
    ?assertMatch({error, {invalid_request, {invalid_method, 123}}},
                 erlmcp_json_rpc:decode_message(Json)).

decode_notification_invalid_method_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"method\":42}">>,
    ?assertMatch({error, {invalid_request, {invalid_method, 42}}},
                 erlmcp_json_rpc:decode_message(Json)).

decode_request_with_list_params_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test\",\"params\":[1,2]}">>,
    {ok, Req} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_request{params = [1, 2]}, Req).

decode_request_with_invalid_params_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test\",\"params\":\"bad\"}">>,
    {ok, Req} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_request{params = undefined}, Req).

decode_string_id_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"result\":true}">>,
    {ok, Resp} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_response{id = <<"abc">>}, Resp).

decode_null_id_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":true}">>,
    {ok, Resp} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_response{id = null}, Resp).

decode_float_id_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":3.14,\"result\":true}">>,
    {ok, Resp} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_response{id = 3.14}, Resp).

decode_error_response_test() ->
    Json = <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32600,\"message\":\"Invalid\"}}">>,
    {ok, Resp} = erlmcp_json_rpc:decode_message(Json),
    ?assertMatch(#json_rpc_response{id = 1, error = #{<<"code">> := -32600}}, Resp).

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
