-module(erlmcp_uri_template_tests).

-include_lib("eunit/include/eunit.hrl").

find_matching_exact_test() ->
    Templates = #{<<"files/{path}">> => #{handler => fun_placeholder}},
    {ok, _, Params} = erlmcp_uri_template:find_matching(<<"files/readme">>, Templates),
    ?assertEqual(#{<<"path">> => <<"readme">>}, Params).

find_matching_multi_param_test() ->
    Templates = #{<<"users/{org}/{name}">> => #{id => multi}},
    {ok, _, Params} = erlmcp_uri_template:find_matching(
        <<"users/acme/alice">>, Templates),
    ?assertEqual(#{<<"org">> => <<"acme">>, <<"name">> => <<"alice">>}, Params).

find_matching_no_match_test() ->
    Templates = #{<<"files/{path}">> => #{handler => h}},
    ?assertEqual(error, erlmcp_uri_template:find_matching(<<"other">>, Templates)).

find_matching_wrong_segment_count_test() ->
    Templates = #{<<"a/{b}/c">> => #{handler => h}},
    ?assertEqual(error, erlmcp_uri_template:find_matching(<<"a/x">>, Templates)).

find_matching_literal_mismatch_test() ->
    Templates = #{<<"api/v1/{id}">> => #{handler => h}},
    ?assertEqual(error, erlmcp_uri_template:find_matching(<<"api/v2/123">>, Templates)).

find_matching_empty_templates_test() ->
    ?assertEqual(error, erlmcp_uri_template:find_matching(<<"any">>, #{})).

find_matching_malformed_template_test() ->
    Templates = #{<<"files/{unclosed">> => #{handler => h}},
    ?assertEqual(error, erlmcp_uri_template:find_matching(<<"files/x">>, Templates)).
