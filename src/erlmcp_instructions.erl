-module(erlmcp_instructions).

-export([generate/1]).

-spec generate([map()]) -> binary().
generate(AllTools) ->
    Tools = [T || T <- AllTools,
                  maps:get(is_directory, T, false) =/= true],
    case Tools of
        [] ->
            <<"This server has no tools registered. Use tools/list to check for updates.">>;
        _ ->
            Categories = lists:usort(
                [maps:get(category, T) || T <- Tools, maps:is_key(category, T)]),
            Explicit = [maps:get(name, T) || T <- Tools,
                            maps:get(entry_point, T, false) =:= true],
            EntryPoints = case Explicit of
                [] ->
                    AllNextTargets = lists:usort(lists:flatten(
                        [maps:get(next, T, []) || T <- Tools])),
                    AllNames = [maps:get(name, T) || T <- Tools],
                    lists:sort([N || N <- AllNames,
                                     not lists:member(N, AllNextTargets)]);
                _ ->
                    lists:sort(Explicit)
            end,
            build_text(Categories, EntryPoints)
    end.

%%====================================================================
%% Internal
%%====================================================================

build_text(Categories, EntryPoints) ->
    CatPart = case Categories of
        [] -> <<>>;
        _ -> <<" Categories: ", (join_bins(Categories, <<", ">>))/binary, ".">>
    end,
    EPPart = case EntryPoints of
        [] -> <<>>;
        _ -> <<" Start with: ", (join_bins(EntryPoints, <<", ">>))/binary, ".">>
    end,
    <<"This server provides tools organized by category.",
      CatPart/binary, EPPart/binary,
      " Use tools/list for the full catalog.">>.

join_bins([H], _) -> H;
join_bins([H | T], Sep) ->
    lists:foldl(fun(B, Acc) -> <<Acc/binary, Sep/binary, B/binary>> end, H, T).
