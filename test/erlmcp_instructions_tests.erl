-module(erlmcp_instructions_tests).

-include_lib("eunit/include/eunit.hrl").

generate_no_tools_test() ->
    Result = erlmcp_instructions:generate([]),
    ?assertEqual(<<"This server has no tools registered. Use tools/list to check for updates.">>,
                 Result).

generate_directory_only_test() ->
    Tools = [#{name => <<"dir">>, is_directory => true}],
    Result = erlmcp_instructions:generate(Tools),
    ?assertEqual(<<"This server has no tools registered. Use tools/list to check for updates.">>,
                 Result).

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
