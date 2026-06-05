-module(erlmcp_inbound_validation_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).

-export([envelope_missing_jsonrpc_field/1,
         envelope_wrong_jsonrpc_version/1,
         valid_envelope_bad_params/1,
         error_response_is_schema_valid/1,
         valid_request_passes/1,
         tools_call_missing_name/1]).

all() ->
    [envelope_missing_jsonrpc_field,
     envelope_wrong_jsonrpc_version,
     valid_envelope_bad_params,
     error_response_is_schema_valid,
     valid_request_passes,
     tools_call_missing_name].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

envelope_missing_jsonrpc_field(_Config) ->
    Msg = jsx:encode(#{<<"id">> => 1, <<"method">> => <<"ping">>}),
    {error, _} = erlmcp_json_rpc:decode_and_classify(Msg).

envelope_wrong_jsonrpc_version(_Config) ->
    Msg = jsx:encode(#{<<"jsonrpc">> => <<"1.0">>, <<"id">> => 1,
                       <<"method">> => <<"ping">>}),
    {error, _} = erlmcp_json_rpc:decode_and_classify(Msg).

valid_envelope_bad_params(_Config) ->
    Msg = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{}),
    {error, {invalid_params, {missing, <<"protocolVersion">>}}} =
        erlmcp_json_rpc:decode_and_classify(Msg).

error_response_is_schema_valid(_Config) ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"val_test">>, version => <<"0.1.0">>
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Server, responder => Responder,
        name => <<"val_test">>, version => <<"0.1.0">>
    }),

    %% Missing jsonrpc field → session sends -32700 (parse error)
    %% because validate_jsonrpc_version rejects it before schema validation
    BadEnvelope = jsx:encode(#{<<"id">> => 1, <<"method">> => <<"ping">>}),
    erlmcp_server_session:send_message(Session, BadEnvelope),
    ErrorJsonEnvelope = receive_json(),
    {ok, DecodedEnvelope} = erlmcp_codec:decode(ErrorJsonEnvelope),
    ErrCode1 = maps:get(<<"code">>, maps:get(<<"error">>, DecodedEnvelope)),
    ?assert(ErrCode1 =:= -32700 orelse ErrCode1 =:= -32600),
    ok = erlmcp_codec:validate_outbound(DecodedEnvelope),

    %% Initialize to reach operational state so we can test param validation
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{},
        <<"clientInfo">> => #{<<"name">> => <<"test">>, <<"version">> => <<"1">>}
    }),
    erlmcp_server_session:send_message(Session, InitReq),
    _InitResp = receive_json(),

    %% Now in operational state: bad params → -32602
    BadParams = erlmcp_json_rpc:encode_request(2, <<"initialize">>, #{}),
    erlmcp_server_session:send_message(Session, BadParams),
    ErrorJson32602 = receive_json(),
    {ok, Decoded32602} = erlmcp_codec:decode(ErrorJson32602),
    ?assertEqual(-32602, maps:get(<<"code">>,
        maps:get(<<"error">>, Decoded32602))),
    ok = erlmcp_codec:validate_outbound(Decoded32602),

    gen_statem:stop(Session),
    gen_server:stop(Server).

valid_request_passes(_Config) ->
    Msg = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
    {ok, {request, 1, <<"ping">>, _}} =
        erlmcp_json_rpc:decode_and_classify(Msg).

tools_call_missing_name(_Config) ->
    Msg = erlmcp_json_rpc:encode_request(1, <<"tools/call">>,
              #{<<"arguments">> => #{}}),
    {error, {invalid_params, {missing, <<"name">>}}} =
        erlmcp_json_rpc:decode_and_classify(Msg).

%%====================================================================
%% Helpers
%%====================================================================

receive_json() ->
    receive
        {send, Json} -> Json
    after 2000 ->
        error(timeout_waiting_for_response)
    end.
