-module(erlmcp_pagination_tests).

-include_lib("eunit/include/eunit.hrl").

paginate_no_cursor_small_list_test() ->
    {Page, undefined} = erlmcp_pagination:paginate([a, b, c], undefined),
    ?assertEqual([a, b, c], Page).

paginate_no_cursor_exact_page_test() ->
    Items = lists:seq(1, 50),
    {Page, undefined} = erlmcp_pagination:paginate(Items, undefined),
    ?assertEqual(Items, Page).

paginate_no_cursor_over_page_test() ->
    Items = lists:seq(1, 55),
    {Page, Cursor} = erlmcp_pagination:paginate(Items, undefined),
    ?assertEqual(50, length(Page)),
    ?assert(is_binary(Cursor)),
    {Page2, undefined} = erlmcp_pagination:paginate(Items, Cursor),
    ?assertEqual([51, 52, 53, 54, 55], Page2).

paginate_empty_test() ->
    {[], undefined} = erlmcp_pagination:paginate([], undefined).

paginated_result_no_cursor_test() ->
    Result = erlmcp_pagination:paginated_result(<<"k">>, [1], undefined),
    ?assertEqual(#{<<"k">> => [1]}, Result).

paginated_result_with_cursor_test() ->
    Result = erlmcp_pagination:paginated_result(<<"k">>, [1], <<"abc">>),
    ?assertEqual(#{<<"k">> => [1], <<"nextCursor">> => <<"abc">>}, Result).
