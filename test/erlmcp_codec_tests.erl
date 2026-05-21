-module(erlmcp_codec_tests).

-include_lib("eunit/include/eunit.hrl").

encode_map_test() ->
    {ok, Bin} = erlmcp_codec:encode(#{<<"key">> => <<"value">>}),
    ?assert(is_binary(Bin)),
    {ok, Decoded} = erlmcp_codec:decode(Bin),
    ?assertEqual(#{<<"key">> => <<"value">>}, Decoded).

encode_list_test() ->
    {ok, Bin} = erlmcp_codec:encode([1, 2, 3]),
    ?assert(is_binary(Bin)).

decode_invalid_json_test() ->
    ?assertMatch({error, _}, erlmcp_codec:decode(<<"not json">>)).

decode_not_binary_test() ->
    ?assertMatch({error, {decode_error, not_binary}}, erlmcp_codec:decode(123)).

roundtrip_test() ->
    Original = #{<<"id">> => 1, <<"method">> => <<"ping">>, <<"params">> => #{}},
    {ok, Encoded} = erlmcp_codec:encode(Original),
    {ok, Decoded} = erlmcp_codec:decode(Encoded),
    ?assertEqual(Original, Decoded).

encode_nested_test() ->
    Term = #{<<"a">> => #{<<"b">> => [1, <<"two">>, true, null]}},
    {ok, Bin} = erlmcp_codec:encode(Term),
    {ok, Decoded} = erlmcp_codec:decode(Bin),
    ?assertEqual(Term, Decoded).

empty_map_roundtrip_test() ->
    {ok, Bin} = erlmcp_codec:encode(#{}),
    {ok, Decoded} = erlmcp_codec:decode(Bin),
    ?assertEqual(#{}, Decoded).
