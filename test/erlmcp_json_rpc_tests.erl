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
