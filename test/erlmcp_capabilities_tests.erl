-module(erlmcp_capabilities_tests).

-include_lib("eunit/include/eunit.hrl").

negotiate_matching_version_test() ->
    ?assertEqual({ok, <<"2025-11-25">>},
                 erlmcp_capabilities:negotiate_version(
                     <<"2025-11-25">>,
                     erlmcp_capabilities:supported_versions())).

negotiate_older_version_test() ->
    ?assertEqual({ok, <<"2024-11-05">>},
                 erlmcp_capabilities:negotiate_version(
                     <<"2024-11-05">>,
                     erlmcp_capabilities:supported_versions())).

negotiate_disjoint_version_test() ->
    ?assertEqual({error, no_common_version},
                 erlmcp_capabilities:negotiate_version(
                     <<"2023-01-01">>,
                     erlmcp_capabilities:supported_versions())).

build_server_capabilities_test() ->
    Registered = #{
        <<"tools">> => #{},
        <<"resources">> => #{<<"subscribe">> => true},
        <<"prompts">> => false
    },
    Caps = erlmcp_capabilities:build_server_capabilities(Registered),
    ?assertMatch(#{<<"tools">> := #{}}, Caps),
    ?assertMatch(#{<<"resources">> := #{<<"subscribe">> := true}}, Caps),
    ?assertNot(maps:is_key(<<"prompts">>, Caps)).

build_with_boolean_true_test() ->
    Caps = erlmcp_capabilities:build_server_capabilities(#{<<"logging">> => true}),
    ?assertEqual(#{<<"logging">> => #{}}, Caps).

empty_registration_test() ->
    ?assertEqual(#{}, erlmcp_capabilities:build_server_capabilities(#{})).

supported_versions_nonempty_test() ->
    Versions = erlmcp_capabilities:supported_versions(),
    ?assert(length(Versions) > 0),
    ?assert(lists:all(fun is_binary/1, Versions)).

build_client_capabilities_test() ->
    Caps = erlmcp_capabilities:build_client_capabilities(#{<<"roots">> => #{}}),
    ?assertEqual(#{<<"roots">> => #{}}, Caps).
