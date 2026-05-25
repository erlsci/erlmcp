-module(erlmcp_codec).

%% The only module that calls jsx directly. The rest of the system uses
%% these functions, keeping the JSON library swappable.

-export([encode/1, decode/1, ensure_utf8/1]).

-spec encode(term()) -> {ok, binary()} | {error, term()}.
encode(Term) ->
    try
        Json = jsx:encode(Term),
        case ensure_utf8(Json) of
            ok -> {ok, Json};
            {error, _} = Err -> Err
        end
    catch
        error:badarg -> {error, {encode_error, badarg}}
    end.

-spec decode(binary()) -> {ok, term()} | {error, term()}.
decode(Bin) when is_binary(Bin) ->
    try
        {ok, jsx:decode(Bin, [return_maps])}
    catch
        error:badarg -> {error, {decode_error, badarg}}
    end;
decode(_) ->
    {error, {decode_error, not_binary}}.

-spec ensure_utf8(binary()) -> ok | {error, invalid_utf8}.
ensure_utf8(Bin) when is_binary(Bin) ->
    case unicode:characters_to_binary(Bin, utf8) of
        Bin -> ok;
        _ -> {error, invalid_utf8}
    end;
ensure_utf8(_) ->
    {error, invalid_utf8}.
