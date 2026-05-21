-module(erlmcp_schema).

-export([object/1, field/3, validate/2]).

-spec object([map()]) -> map().
object(Fields) when is_list(Fields) ->
    #{type => object, properties => Fields}.

-spec field(binary(), atom(), [term()]) -> map().
field(Name, Type, Opts) when is_binary(Name), is_atom(Type), is_list(Opts) ->
    #{name => Name, type => Type, opts => Opts}.

-spec validate(map(), map()) -> ok | {error, term()}.
validate(_Schema, _Data) ->
    ok.
