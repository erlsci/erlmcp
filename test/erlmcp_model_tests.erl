-module(erlmcp_model_tests).

-include_lib("eunit/include/eunit.hrl").

request_roundtrip_test() ->
    Req = erlmcp_model:make_request(1, <<"initialize">>, #{<<"key">> => <<"val">>}),
    ?assertEqual(1, erlmcp_model:request_id(Req)),
    ?assertEqual(<<"initialize">>, erlmcp_model:request_method(Req)),
    ?assertEqual(#{<<"key">> => <<"val">>}, erlmcp_model:request_params(Req)).

request_no_params_test() ->
    Req = erlmcp_model:make_request(42, <<"ping">>, undefined),
    ?assertEqual(42, erlmcp_model:request_id(Req)),
    ?assertEqual(undefined, erlmcp_model:request_params(Req)).

response_result_test() ->
    Resp = erlmcp_model:make_response(1, #{<<"ok">> => true}),
    ?assertEqual(1, erlmcp_model:response_id(Resp)),
    ?assertEqual(#{<<"ok">> => true}, erlmcp_model:response_result(Resp)),
    ?assertNot(erlmcp_model:is_error_response(Resp)).

response_error_test() ->
    Err = erlmcp_model:make_error(-32600, <<"Invalid Request">>, undefined),
    Resp = erlmcp_model:make_error_response(1, Err),
    ?assert(erlmcp_model:is_error_response(Resp)),
    ?assertEqual(undefined, erlmcp_model:response_result(Resp)),
    RpcErr = erlmcp_model:response_error(Resp),
    ?assertEqual(-32600, erlmcp_model:error_code(RpcErr)),
    ?assertEqual(<<"Invalid Request">>, erlmcp_model:error_message(RpcErr)).

notification_test() ->
    Notif = erlmcp_model:make_notification(<<"notifications/cancelled">>, #{<<"id">> => 5}),
    ?assertEqual(<<"notifications/cancelled">>, erlmcp_model:notification_method(Notif)),
    ?assertEqual(#{<<"id">> => 5}, erlmcp_model:notification_params(Notif)).

error_data_test() ->
    Err = erlmcp_model:make_error(-32603, <<"Internal error">>, <<"stack trace">>),
    ?assertEqual(<<"stack trace">>, erlmcp_model:error_data(Err)).

capabilities_test() ->
    Caps = erlmcp_model:make_capabilities(#{<<"tools">> => #{}, <<"resources">> => #{}}),
    ?assert(erlmcp_model:has_capability(Caps, <<"tools">>)),
    ?assert(erlmcp_model:has_capability(Caps, <<"resources">>)),
    ?assertNot(erlmcp_model:has_capability(Caps, <<"prompts">>)),
    ?assertEqual(#{<<"tools">> => #{}, <<"resources">> => #{}},
                 erlmcp_model:capabilities_to_map(Caps)).

peer_info_test() ->
    Server = erlmcp_model:make_server_info(<<"erlmcp">>, <<"0.6.0">>),
    ?assertEqual(<<"erlmcp">>, erlmcp_model:info_name(Server)),
    ?assertEqual(<<"0.6.0">>, erlmcp_model:info_version(Server)),
    Client = erlmcp_model:make_client_info(<<"test-client">>, <<"1.0">>),
    ?assertEqual(<<"test-client">>, erlmcp_model:info_name(Client)).
