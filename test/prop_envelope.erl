-module(prop_envelope).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Generators
%%====================================================================

json_rpc_id() ->
    oneof([pos_integer(), json_string(), null]).

method() ->
    oneof([<<"ping">>, <<"initialize">>, <<"tools/list">>, <<"tools/call">>,
           <<"resources/list">>, <<"resources/read">>, <<"prompts/list">>,
           <<"prompts/get">>, <<"notifications/cancelled">>,
           <<"notifications/initialized">>, <<"notifications/progress">>]).

json_string() ->
    ?LET(S, list(range($a, $z)), list_to_binary(S)).

json_key() ->
    ?SUCHTHAT(K, json_string(), byte_size(K) > 0).

simple_json_value() ->
    oneof([json_string(), integer(), boolean(), null]).

json_map() ->
    ?LET(Pairs, list({json_key(), simple_json_value()}),
         maps:from_list(Pairs)).

%%====================================================================
%% Properties
%%====================================================================

prop_request_roundtrip() ->
    ?FORALL({Id, Method, Params},
            {json_rpc_id(), method(), json_map()},
            begin
                Encoded = erlmcp_json_rpc:encode_request(Id, Method, Params),
                case erlmcp_json_rpc:decode_and_classify(Encoded) of
                    {ok, {request, DecodedId, DecodedMethod, _DecodedParams}} ->
                        DecodedId =:= Id andalso DecodedMethod =:= Method;
                    _ ->
                        false
                end
            end).

prop_response_roundtrip() ->
    ?FORALL({Id, Result},
            {json_rpc_id(), json_map()},
            begin
                Encoded = erlmcp_json_rpc:encode_response(Id, Result),
                case erlmcp_json_rpc:decode_and_classify(Encoded) of
                    {ok, {response, DecodedId, _DecodedResult}} ->
                        DecodedId =:= Id;
                    _ ->
                        false
                end
            end).

prop_error_response_roundtrip() ->
    ?FORALL({Id, Code, Msg},
            {json_rpc_id(), integer(-32700, -32000), json_string()},
            begin
                Encoded = erlmcp_json_rpc:encode_error_response(Id, Code, Msg),
                case erlmcp_json_rpc:decode_and_classify(Encoded) of
                    {ok, {error_response, DecodedId, ErrorMap}} ->
                        DecodedId =:= Id andalso
                        maps:get(<<"code">>, ErrorMap) =:= Code andalso
                        maps:get(<<"message">>, ErrorMap) =:= Msg;
                    _ ->
                        false
                end
            end).

prop_notification_roundtrip() ->
    ?FORALL({Method, Params},
            {method(), json_map()},
            begin
                Encoded = erlmcp_json_rpc:encode_notification(Method, Params),
                case erlmcp_json_rpc:decode_and_classify(Encoded) of
                    {ok, {notification, DecodedMethod, _DecodedParams}} ->
                        DecodedMethod =:= Method;
                    _ ->
                        false
                end
            end).

prop_codec_roundtrip() ->
    ?FORALL(Term, json_map(),
            begin
                {ok, Encoded} = erlmcp_codec:encode(Term),
                {ok, Decoded} = erlmcp_codec:decode(Encoded),
                Decoded =:= Term
            end).

prop_batch_roundtrip() ->
    ?FORALL(Messages, non_empty(list(oneof([
                {request, json_rpc_id(), method(), json_map()},
                {notification, method(), json_map()}
            ]))),
            begin
                Encoded = lists:map(fun
                    ({request, Id, M, P}) -> erlmcp_json_rpc:encode_request(Id, M, P);
                    ({notification, M, P}) -> erlmcp_json_rpc:encode_notification(M, P)
                end, Messages),
                Batch = erlmcp_json_rpc:encode_batch(Encoded),
                case erlmcp_json_rpc:decode_and_classify_any(Batch) of
                    {ok, {batch, Items}} ->
                        length(Items) =:= length(Messages);
                    _ ->
                        false
                end
            end).

prop_malformed_batch_degrades() ->
    ?FORALL(Junk, binary(),
            begin
                case erlmcp_json_rpc:decode_and_classify_any(Junk) of
                    {ok, _} -> true;
                    {error, _} -> true
                end
            end).

%%====================================================================
%% EUnit wrappers (so rebar3 eunit also runs them)
%%====================================================================

envelope_request_roundtrip_test() ->
    ?assert(proper:quickcheck(prop_request_roundtrip(), [quiet, {numtests, 100}])).

envelope_response_roundtrip_test() ->
    ?assert(proper:quickcheck(prop_response_roundtrip(), [quiet, {numtests, 100}])).

envelope_error_response_roundtrip_test() ->
    ?assert(proper:quickcheck(prop_error_response_roundtrip(), [quiet, {numtests, 100}])).

envelope_notification_roundtrip_test() ->
    ?assert(proper:quickcheck(prop_notification_roundtrip(), [quiet, {numtests, 100}])).

envelope_batch_roundtrip_test() ->
    ?assert(proper:quickcheck(prop_batch_roundtrip(), [quiet, {numtests, 100}])).

envelope_malformed_batch_degrades_test() ->
    ?assert(proper:quickcheck(prop_malformed_batch_degrades(), [quiet, {numtests, 100}])).

envelope_codec_roundtrip_test() ->
    ?assert(proper:quickcheck(prop_codec_roundtrip(), [quiet, {numtests, 100}])).
