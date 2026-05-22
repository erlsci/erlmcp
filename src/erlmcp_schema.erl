-module(erlmcp_schema).

%% JSON Schema builder + jesse validator (Phase 2 §1a).
%% Functions over data: builds a schema map AND validates against it.

-export([
    object/1, object/2,
    field/2, field/3,
    string/0, string/1,
    integer/0, integer/1,
    number/0, number/1,
    boolean/0,
    array/1, array/2,
    enum/1,
    any_of/1,
    ref/1,
    validate/2
]).

-type schema() :: map().
-type field_opt() :: required | {default, term()} | {doc, binary()}
    | {min, number()} | {max, number()}
    | {min_length, non_neg_integer()} | {max_length, non_neg_integer()}
    | {pattern, binary()}
    | {min_items, non_neg_integer()} | {max_items, non_neg_integer()}.

-export_type([schema/0, field_opt/0]).

%%====================================================================
%% Type constructors
%%====================================================================

-spec string() -> schema().
string() -> #{<<"type">> => <<"string">>}.

-spec string([field_opt()]) -> schema().
string(Opts) -> apply_constraints(string(), Opts).

-spec integer() -> schema().
integer() -> #{<<"type">> => <<"integer">>}.

-spec integer([field_opt()]) -> schema().
integer(Opts) -> apply_constraints(integer(), Opts).

-spec number() -> schema().
number() -> #{<<"type">> => <<"number">>}.

-spec number([field_opt()]) -> schema().
number(Opts) -> apply_constraints(number(), Opts).

-spec boolean() -> schema().
boolean() -> #{<<"type">> => <<"boolean">>}.

-spec array(schema()) -> schema().
array(ItemSchema) ->
    #{<<"type">> => <<"array">>, <<"items">> => ItemSchema}.

-spec array(schema(), [field_opt()]) -> schema().
array(ItemSchema, Opts) ->
    apply_constraints(array(ItemSchema), Opts).

-spec enum([binary() | atom()]) -> schema().
enum(Values) ->
    Bins = [to_bin(V) || V <- Values],
    #{<<"enum">> => Bins}.

-spec any_of([schema()]) -> schema().
any_of(Schemas) when is_list(Schemas) ->
    #{<<"anyOf">> => Schemas}.

-spec ref(binary()) -> schema().
ref(Ref) when is_binary(Ref) ->
    #{<<"$ref">> => Ref}.

%%====================================================================
%% Object builder
%%====================================================================

-spec object([{binary(), schema(), [field_opt()]}]) -> schema().
object(Fields) ->
    object(Fields, []).

-spec object([{binary(), schema(), [field_opt()]}], [field_opt()]) -> schema().
object(Fields, _Opts) ->
    {Props, Required} = lists:foldl(
        fun({Name, TypeSchema, FieldOpts}, {PAcc, RAcc}) ->
            Schema = apply_field_opts(TypeSchema, FieldOpts),
            NewRAcc = case lists:member(required, FieldOpts) of
                true -> [Name | RAcc];
                false -> RAcc
            end,
            {PAcc#{Name => Schema}, NewRAcc}
        end,
        {#{}, []},
        Fields
    ),
    Base = #{<<"type">> => <<"object">>, <<"properties">> => Props},
    case Required of
        [] -> Base;
        _ -> Base#{<<"required">> => lists:reverse(Required)}
    end.

-spec field(binary(), schema()) -> {binary(), schema(), []}.
field(Name, TypeSchema) when is_binary(Name) ->
    {Name, TypeSchema, []}.

-spec field(binary(), schema(), [field_opt()]) -> {binary(), schema(), [field_opt()]}.
field(Name, TypeSchema, Opts) when is_binary(Name), is_list(Opts) ->
    {Name, TypeSchema, Opts}.

%%====================================================================
%% Validation (jesse wrapper)
%%====================================================================

-spec validate(schema(), term()) -> ok | {error, term()}.
validate(Schema, Data) ->
    case jesse:validate_with_schema(Schema, Data) of
        {ok, _} -> ok;
        {error, Errors} -> {error, {validation_failed, Errors}}
    end.

%%====================================================================
%% Internal
%%====================================================================

apply_field_opts(Schema, Opts) ->
    lists:foldl(fun apply_one_opt/2, Schema, Opts).

apply_constraints(Schema, Opts) ->
    lists:foldl(fun apply_one_opt/2, Schema, Opts).

apply_one_opt(required, S) -> S;
apply_one_opt({default, V}, S) -> S#{<<"default">> => V};
apply_one_opt({doc, D}, S) -> S#{<<"description">> => D};
apply_one_opt({min, V}, S) -> S#{<<"minimum">> => V};
apply_one_opt({max, V}, S) -> S#{<<"maximum">> => V};
apply_one_opt({min_length, V}, S) -> S#{<<"minLength">> => V};
apply_one_opt({max_length, V}, S) -> S#{<<"maxLength">> => V};
apply_one_opt({pattern, V}, S) -> S#{<<"pattern">> => V};
apply_one_opt({min_items, V}, S) -> S#{<<"minItems">> => V};
apply_one_opt({max_items, V}, S) -> S#{<<"maxItems">> => V};
apply_one_opt(_, S) -> S.

to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_atom(V) -> atom_to_binary(V, utf8).
