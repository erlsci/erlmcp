-module(erlmcp_schema_tests).

-include_lib("eunit/include/eunit.hrl").

object_basic_test() ->
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"name">>, erlmcp_schema:string(), [required]),
        erlmcp_schema:field(<<"age">>, erlmcp_schema:integer(), [])
    ]),
    ?assertMatch(#{<<"type">> := <<"object">>, <<"properties">> := _}, Schema),
    ?assertMatch(#{<<"required">> := [<<"name">>]}, Schema).

validate_conforming_test() ->
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"location">>, erlmcp_schema:string(), [required]),
        erlmcp_schema:field(<<"units">>, erlmcp_schema:enum([<<"c">>, <<"f">>]), [])
    ]),
    ?assertEqual(ok, erlmcp_schema:validate(Schema, #{<<"location">> => <<"London">>})),
    ?assertEqual(ok, erlmcp_schema:validate(Schema,
        #{<<"location">> => <<"NYC">>, <<"units">> => <<"f">>})).

validate_nonconforming_test() ->
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"location">>, erlmcp_schema:string(), [required])
    ]),
    ?assertMatch({error, _}, erlmcp_schema:validate(Schema, #{})).

string_constraints_test() ->
    Schema = erlmcp_schema:string([{min_length, 3}, {max_length, 10}]),
    ?assertMatch(#{<<"minLength">> := 3, <<"maxLength">> := 10}, Schema).

integer_constraints_test() ->
    Schema = erlmcp_schema:integer([{min, 0}, {max, 100}]),
    ?assertMatch(#{<<"minimum">> := 0, <<"maximum">> := 100}, Schema).

number_test() ->
    Schema = erlmcp_schema:number(),
    ?assertEqual(#{<<"type">> => <<"number">>}, Schema).

boolean_test() ->
    Schema = erlmcp_schema:boolean(),
    ?assertEqual(#{<<"type">> => <<"boolean">>}, Schema).

array_test() ->
    Schema = erlmcp_schema:array(erlmcp_schema:string()),
    ?assertMatch(#{<<"type">> := <<"array">>, <<"items">> := #{<<"type">> := <<"string">>}}, Schema).

array_constraints_test() ->
    Schema = erlmcp_schema:array(erlmcp_schema:integer(), [{min_items, 1}, {max_items, 5}]),
    ?assertMatch(#{<<"minItems">> := 1, <<"maxItems">> := 5}, Schema).

enum_test() ->
    Schema = erlmcp_schema:enum([<<"a">>, <<"b">>]),
    ?assertEqual(#{<<"enum">> => [<<"a">>, <<"b">>]}, Schema).

enum_atom_test() ->
    Schema = erlmcp_schema:enum([celsius, fahrenheit]),
    ?assertEqual(#{<<"enum">> => [<<"celsius">>, <<"fahrenheit">>]}, Schema).

any_of_test() ->
    Schema = erlmcp_schema:any_of([erlmcp_schema:string(), erlmcp_schema:integer()]),
    ?assertMatch(#{<<"anyOf">> := [_, _]}, Schema).

ref_test() ->
    Schema = erlmcp_schema:ref(<<"#/definitions/Foo">>),
    ?assertEqual(#{<<"$ref">> => <<"#/definitions/Foo">>}, Schema).

field_with_doc_test() ->
    {Name, TypeSchema, _Opts} = erlmcp_schema:field(<<"city">>, erlmcp_schema:string(),
        [required, {doc, <<"City name">>}]),
    ?assertEqual(<<"city">>, Name),
    ?assertMatch(#{<<"type">> := <<"string">>}, TypeSchema).

object_no_required_test() ->
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"opt1">>, erlmcp_schema:string()),
        erlmcp_schema:field(<<"opt2">>, erlmcp_schema:integer())
    ]),
    ?assertNot(maps:is_key(<<"required">>, Schema)).

default_value_test() ->
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"units">>, erlmcp_schema:enum([<<"c">>, <<"f">>]),
            [{default, <<"c">>}])
    ]),
    Props = maps:get(<<"properties">>, Schema),
    UnitsSchema = maps:get(<<"units">>, Props),
    ?assertEqual(<<"c">>, maps:get(<<"default">>, UnitsSchema)).

jesse_integration_test() ->
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"x">>, erlmcp_schema:number(), [required]),
        erlmcp_schema:field(<<"y">>, erlmcp_schema:number(), [required])
    ]),
    ?assertEqual(ok, erlmcp_schema:validate(Schema, #{<<"x">> => 1.5, <<"y">> => 2.5})),
    ?assertMatch({error, _}, erlmcp_schema:validate(Schema, #{<<"x">> => 1.5})),
    ?assertMatch({error, _}, erlmcp_schema:validate(Schema, #{<<"x">> => <<"not a number">>, <<"y">> => 1})).
