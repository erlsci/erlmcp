-module(erlmcp_codec).

%% The only module that calls jsx directly. The rest of the system uses
%% these functions, keeping the JSON library swappable.

-export([encode/1, decode/1]).

-spec encode(term()) -> {ok, binary()} | {error, term()}.
encode(Term) ->
    try
        {ok, jsx:encode(Term)}
    catch
        error:badarg -> {error, {encode_error, badarg}}
    end.

-spec decode(binary()) -> {ok, term()} | {error, term()}.
decode(Bin) when is_binary(Bin) ->
    try
        {ok, jsx:decode(Bin, [return_maps])}
    catch
        _:_ -> {error, {decode_error, badarg}}
    end;
decode(_) ->
    {error, {decode_error, not_binary}}.
