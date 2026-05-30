-module(erlmcp_instructions).

-export([generate/1, generate/2]).

-spec generate([map()]) -> binary().
generate(AllTools) ->
    generate(#{}, AllTools).

-spec generate(map(), [map()]) -> binary().
generate(ServerIdentity, AllTools) ->
    Tools = [T || T <- AllTools,
                  maps:get(is_directory, T, false) =/= true],
    case Tools of
        [] ->
            <<"This server has no tools registered. ",
              "Use the directory tool for an oriented overview.">>;
        _ ->
            Lines = build_lines(ServerIdentity, Tools),
            join_lines(Lines)
    end.

%%====================================================================
%% Internal
%%====================================================================

build_lines(ServerIdentity, Tools) ->
    IdentityLines = identity_lines(ServerIdentity),
    Categories = lists:usort(
        [maps:get(category, T) || T <- Tools, maps:is_key(category, T)]),
    EntryPoints = find_entry_points(Tools),
    FeatureLines = protocol_feature_lines(Tools),
    CatLine = case Categories of
        [] -> [];
        _ -> [<<"Categories: ", (join_bins(Categories, <<", ">>))/binary, ".">>]
    end,
    EPLine = case EntryPoints of
        [] -> [];
        _ -> [<<"Start with: ", (join_bins(EntryPoints, <<", ">>))/binary, ".">>]
    end,
    DirectoryLine = [<<"Call the directory tool for an oriented overview ",
                       "with workflow hints and protocol feature details.">>],
    IdentityLines ++ CatLine ++ EPLine ++ FeatureLines ++ DirectoryLine.

identity_lines(Identity) ->
    Name = maps:get(name, Identity, undefined),
    Purpose = maps:get(purpose, Identity, undefined),
    Version = maps:get(version, Identity, undefined),
    Source = maps:get(source, Identity, undefined),
    NameLine = case {Name, Version} of
        {undefined, _} -> [];
        {N, undefined} -> [N];
        {N, V} -> [<<N/binary, " v", V/binary>>]
    end,
    PurposeLine = case Purpose of
        undefined -> [];
        P -> [P]
    end,
    SourceLine = case Source of
        undefined -> [];
        S -> [<<"Source: ", S/binary>>]
    end,
    NameLine ++ PurposeLine ++ SourceLine.

find_entry_points(Tools) ->
    Explicit = [maps:get(name, T) || T <- Tools,
                    maps:get(entry_point, T, false) =:= true],
    case Explicit of
        [] ->
            AllNextTargets = lists:usort(lists:flatten(
                [maps:get(next, T, []) || T <- Tools])),
            AllNames = [maps:get(name, T) || T <- Tools],
            lists:sort([N || N <- AllNames,
                             not lists:member(N, AllNextTargets)]);
        _ ->
            lists:sort(Explicit)
    end.

protocol_feature_lines(Tools) ->
    FeatureMap = lists:foldl(fun(T, Acc) ->
        case maps:get(protocol_features, T, []) of
            [] -> Acc;
            PFs ->
                Name = maps:get(name, T),
                lists:foldl(fun(F, A) ->
                    FB = atom_to_binary(F),
                    Existing = maps:get(FB, A, []),
                    A#{FB => [Name | Existing]}
                end, Acc, PFs)
        end
    end, #{}, Tools),
    case maps:size(FeatureMap) of
        0 -> [];
        _ ->
            Summaries = maps:fold(fun(Feature, ToolNames, Acc) ->
                Names = join_bins(lists:reverse(ToolNames), <<", ">>),
                [<<Feature/binary, ": ", Names/binary>> | Acc]
            end, [], FeatureMap),
            [<<"Protocol features: ",
              (join_bins(lists:sort(Summaries), <<"; ">>))/binary, ".">>]
    end.

join_lines(Lines) ->
    iolist_to_binary(lists:join($\n, Lines)).

join_bins([H], _) -> H;
join_bins([H | T], Sep) ->
    lists:foldl(fun(B, Acc) -> <<Acc/binary, Sep/binary, B/binary>> end, H, T).
