-module(erlmcp_pagination).

-export([paginate/2, paginated_result/3]).

-spec paginate([term()], binary() | undefined) -> {[term()], binary() | undefined}.
paginate(Items, undefined) ->
    paginate_from(Items, 0, 50);
paginate(Items, Cursor) ->
    Offset = binary_to_integer(base64:decode(Cursor)),
    paginate_from(Items, Offset, 50).

-spec paginated_result(binary(), [term()], binary() | undefined) -> map().
paginated_result(Key, Items, undefined) ->
    #{Key => Items};
paginated_result(Key, Items, NextCursor) ->
    #{Key => Items, <<"nextCursor">> => NextCursor}.

%%====================================================================
%% Internal
%%====================================================================

paginate_from(Items, Offset, PageSize) ->
    Remaining = safe_nthtail(Offset, Items),
    case safe_split(PageSize, Remaining) of
        {Page, [_ | _]} ->
            NextCursor = base64:encode(integer_to_binary(Offset + PageSize)),
            {Page, NextCursor};
        {Page, []} ->
            {Page, undefined}
    end.

safe_nthtail(0, L) -> L;
safe_nthtail(_, []) -> [];
safe_nthtail(N, [_ | T]) -> safe_nthtail(N - 1, T).

safe_split(N, L) -> safe_split(N, L, []).
safe_split(0, L, Acc) -> {lists:reverse(Acc), L};
safe_split(_, [], Acc) -> {lists:reverse(Acc), []};
safe_split(N, [H | T], Acc) -> safe_split(N - 1, T, [H | Acc]).
