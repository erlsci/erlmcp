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
    validate/2,
    load_protocol_schema/0,
    protocol_definition/1,
    validate_protocol/2,
    find_existing/1
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
%% Protocol schema (MCP 2025-11-25)
%%====================================================================

-spec load_protocol_schema() -> {ok, map()} | {error, term()}.
load_protocol_schema() ->
    case schema_path() of
        {ok, Path} ->
            case file:read_file(Path) of
                {ok, Bin} ->
                    case erlmcp_codec:decode(Bin) of
                        {ok, Schema} when is_map(Schema) ->
                            {ok, maps:get(<<"definitions">>, Schema, #{})};
                        {ok, _} ->
                            {error, {bad_schema, not_object}};
                        {error, _} = Err ->
                            Err
                    end;
                {error, _} = Err ->
                    Err
            end;
        {error, _} = Err ->
            Err
    end.

-spec protocol_definition(binary()) -> {ok, map()} | {error, term()}.
protocol_definition(Name) when is_binary(Name) ->
    case load_protocol_schema() of
        {ok, Defs} ->
            case maps:find(Name, Defs) of
                {ok, Def} -> {ok, Def};
                error -> {error, {definition_not_found, Name}}
            end;
        {error, _} = Err ->
            Err
    end.

-spec validate_protocol(binary(), term()) -> ok | {error, term()}.
validate_protocol(DefinitionName, Data) when is_binary(DefinitionName) ->
    case protocol_definition(DefinitionName) of
        {ok, Schema} -> validate(Schema, Data);
        {error, _} = Err -> Err
    end.

%%====================================================================
%% Internal
%%====================================================================

schema_path() ->
    Candidates = case code:priv_dir(erlmcp) of
        {error, _} -> [];
        PrivDir -> [filename:join([PrivDir, "schema", "mcp-2025-11-25.json"])]
    end,
    find_existing(Candidates).

find_existing([]) ->
    {error, schema_file_not_found};
find_existing([Path | Rest]) ->
    case filelib:is_regular(Path) of
        true -> {ok, Path};
        false -> find_existing(Rest)
    end.

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
