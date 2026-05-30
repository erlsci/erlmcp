-module(erlmcp_instructions_tests).

-include_lib("eunit/include/eunit.hrl").

generate_no_tools_test() ->
    Result = erlmcp_instructions:generate([]),
    ?assert(binary:match(Result, <<"no tools registered">>) =/= nomatch),
    ?assert(binary:match(Result, <<"directory">>) =/= nomatch).

generate_directory_only_test() ->
    Tools = [#{name => <<"dir">>, is_directory => true}],
    Result = erlmcp_instructions:generate(Tools),
    ?assert(binary:match(Result, <<"no tools registered">>) =/= nomatch).

generate_with_categories_test() ->
    Tools = [#{name => <<"t1">>, category => <<"math">>},
             #{name => <<"t2">>, category => <<"text">>}],
    Result = erlmcp_instructions:generate(Tools),
    ?assert(binary:match(Result, <<"Categories:">>) =/= nomatch).

generate_with_entry_points_test() ->
    Tools = [#{name => <<"start">>, entry_point => true},
             #{name => <<"helper">>}],
    Result = erlmcp_instructions:generate(Tools),
    ?assert(binary:match(Result, <<"Start with: start">>) =/= nomatch).

generate_inferred_entry_points_test() ->
    Tools = [#{name => <<"root">>},
             #{name => <<"leaf">>, next => []}],
    Result = erlmcp_instructions:generate(Tools),
    ?assert(binary:match(Result, <<"Start with:">>) =/= nomatch).

generate_next_chain_test() ->
    Tools = [#{name => <<"a">>, next => [<<"b">>]},
             #{name => <<"b">>}],
    Result = erlmcp_instructions:generate(Tools),
    ?assert(binary:match(Result, <<"Start with: a">>) =/= nomatch).

generate_with_identity_test() ->
    Identity = #{name => <<"calc">>, version => <<"2.0">>,
                 purpose => <<"A calculator server">>},
    Tools = [#{name => <<"add">>, category => <<"math">>}],
    Result = erlmcp_instructions:generate(Identity, Tools),
    ?assert(binary:match(Result, <<"calc v2.0">>) =/= nomatch),
    ?assert(binary:match(Result, <<"A calculator server">>) =/= nomatch).

generate_with_source_test() ->
    Identity = #{name => <<"srv">>, source => <<"https://example.com">>},
    Tools = [#{name => <<"t">>}],
    Result = erlmcp_instructions:generate(Identity, Tools),
    ?assert(binary:match(Result, <<"Source: https://example.com">>) =/= nomatch).

generate_with_protocol_features_test() ->
    Tools = [#{name => <<"slow">>, protocol_features => [tasks, progress]},
             #{name => <<"ask">>, protocol_features => [sampling]}],
    Result = erlmcp_instructions:generate(#{}, Tools),
    ?assert(binary:match(Result, <<"Protocol features:">>) =/= nomatch),
    ?assert(binary:match(Result, <<"sampling">>) =/= nomatch),
    ?assert(binary:match(Result, <<"tasks">>) =/= nomatch).

generate_points_to_directory_test() ->
    Tools = [#{name => <<"t">>}],
    Result = erlmcp_instructions:generate(Tools),
    ?assert(binary:match(Result, <<"directory">>) =/= nomatch).

generate_identity_name_only_test() ->
    Identity = #{name => <<"minimal">>},
    Tools = [#{name => <<"t">>}],
    Result = erlmcp_instructions:generate(Identity, Tools),
    ?assert(binary:match(Result, <<"minimal">>) =/= nomatch).

generate_empty_identity_test() ->
    Result = erlmcp_instructions:generate(#{}, [#{name => <<"t">>}]),
    ?assert(binary:match(Result, <<"directory">>) =/= nomatch).
