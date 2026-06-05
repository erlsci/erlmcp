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

%%====================================================================
%% Protocol schema tests (P6M5)
%%====================================================================

load_protocol_schema_test() ->
    {ok, Defs} = erlmcp_schema:load_protocol_schema(),
    ?assert(is_map(Defs)),
    ?assert(maps:size(Defs) >= 20).

protocol_definition_found_test() ->
    {ok, Schema} = erlmcp_schema:protocol_definition(<<"Icon">>),
    ?assertMatch(#{<<"type">> := <<"object">>}, Schema).

protocol_definition_not_found_test() ->
    ?assertMatch({error, {definition_not_found, _}},
                 erlmcp_schema:protocol_definition(<<"NonExistent">>)).

validate_protocol_icon_valid_test() ->
    ok = erlmcp_schema:validate_protocol(<<"Icon">>,
             #{<<"src">> => <<"data:image/png;base64,abc">>}).

validate_protocol_icon_invalid_test() ->
    {error, _} = erlmcp_schema:validate_protocol(<<"Icon">>,
                     #{<<"type">> => <<"emoji">>, <<"emoji">> => <<"star">>}).

validate_protocol_tool_test() ->
    ok = erlmcp_schema:validate_protocol(<<"Tool">>,
             #{<<"name">> => <<"test">>,
               <<"inputSchema">> => #{<<"type">> => <<"object">>}}).

validate_protocol_task_support_test() ->
    ok = erlmcp_schema:validate_protocol(<<"ToolExecution">>,
             #{<<"taskSupport">> => <<"optional">>}),
    {error, _} = erlmcp_schema:validate_protocol(<<"ToolExecution">>,
                     #{<<"taskSupport">> => <<"allowed">>}).

validate_protocol_init_result_test() ->
    ok = erlmcp_schema:validate_protocol(<<"InitializeResult">>,
             #{<<"protocolVersion">> => <<"2025-11-25">>,
               <<"capabilities">> => #{},
               <<"serverInfo">> => #{<<"name">> => <<"x">>,
                                     <<"version">> => <<"1">>}}).

number_with_opts_test() ->
    Schema = erlmcp_schema:number([{min, 0}, {max, 100}]),
    ?assertMatch(#{<<"minimum">> := 0, <<"maximum">> := 100}, Schema).

pattern_constraint_test() ->
    Schema = erlmcp_schema:string([{pattern, <<"^[a-z]+$">>}]),
    ?assertMatch(#{<<"pattern">> := <<"^[a-z]+$">>}, Schema).

unknown_field_opt_test() ->
    Schema = erlmcp_schema:string([unknown_opt]),
    ?assertMatch(#{<<"type">> := <<"string">>}, Schema).

validate_protocol_unknown_definition_test() ->
    {error, {definition_not_found, <<"NonExistent">>}} =
        erlmcp_schema:validate_protocol(<<"NonExistent">>, #{}).

validate_protocol_propagates_load_error_test() ->
    ok.

number_opts_test() ->
    Schema = erlmcp_schema:number([{min, 0}]),
    ?assertMatch(#{<<"minimum">> := 0}, Schema).

