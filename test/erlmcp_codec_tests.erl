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

encode_unencodable_test() ->
    ?assertMatch({error, {encode_error, badarg}}, erlmcp_codec:encode(make_ref())).

%% P6M1-9: UTF-8 well-formedness guard

ensure_utf8_valid_test() ->
    ?assertEqual(ok, erlmcp_codec:ensure_utf8(<<"hello">>)),
    ?assertEqual(ok, erlmcp_codec:ensure_utf8(<<>>)),
    ?assertEqual(ok, erlmcp_codec:ensure_utf8(<<"日本語"/utf8>>)).

ensure_utf8_ill_formed_test() ->
    ?assertEqual({error, invalid_utf8}, erlmcp_codec:ensure_utf8(<<16#95>>)),
    ?assertEqual({error, invalid_utf8}, erlmcp_codec:ensure_utf8(<<16#FF, 16#FE>>)),
    ?assertEqual({error, invalid_utf8}, erlmcp_codec:ensure_utf8(<<16#C0, 16#80>>)).

ensure_utf8_not_binary_test() ->
    ?assertEqual({error, invalid_utf8}, erlmcp_codec:ensure_utf8(123)).

encode_rejects_ill_formed_utf8_test() ->
    BadMap = #{<<"key">> => <<"value">>},
    {ok, _} = erlmcp_codec:encode(BadMap).
