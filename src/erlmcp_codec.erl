-module(erlmcp_codec).

-export([encode/1, decode/1]).

-spec encode(term()) -> binary().
encode(Term) ->
    jsx:encode(Term).

-spec decode(binary()) -> term().
decode(Bin) when is_binary(Bin) ->
    jsx:decode(Bin, [return_maps]).
