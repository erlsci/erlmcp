-module(erlmcp_uri_template).

-export([find_matching/2]).

-spec find_matching(binary(), #{binary() => map()}) ->
    {ok, map(), map()} | error.
find_matching(Uri, Templates) ->
    maps:fold(fun(UriTemplate, Spec, error) ->
        case match(UriTemplate, Uri) of
            {ok, Params} -> {ok, Spec, Params};
            error -> error
        end;
    (_UriTemplate, _Spec, Found) -> Found
    end, error, Templates).

%%====================================================================
%% Internal
%%====================================================================

-spec match(binary(), binary()) -> {ok, map()} | error.
match(Template, Uri) ->
    TParts = binary:split(Template, <<"/">>, [global]),
    UParts = binary:split(Uri, <<"/">>, [global]),
    case length(TParts) =:= length(UParts) of
        false -> error;
        true -> match_parts(TParts, UParts, #{})
    end.

match_parts([], [], Acc) -> {ok, Acc};
match_parts([TPart | TRest], [UPart | URest], Acc) ->
    case TPart of
        <<"{", Rest/binary>> ->
            case binary:split(Rest, <<"}">>) of
                [ParamName, <<>>] ->
                    match_parts(TRest, URest, Acc#{ParamName => UPart});
                _ -> error
            end;
        UPart ->
            match_parts(TRest, URest, Acc);
        _ -> error
    end.
