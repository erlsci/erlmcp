-module(erlmcp_validation_regression_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).

-export([icon_buggy_shape_rejected/1,
         icon_valid_data_uri_accepted/1,
         task_support_invalid_enum_rejected/1,
         task_support_valid_enums_accepted/1,
         utf8_malformed_caught/1,
         utf8_wellformed_accepted/1,
         schema_load_test/1,
         schema_definitions_present/1,
         icon_extra_fields_rejected/1,
         outbound_tools_list_validated/1]).

all() ->
    [icon_buggy_shape_rejected,
     icon_valid_data_uri_accepted,
     icon_extra_fields_rejected,
     task_support_invalid_enum_rejected,
     task_support_valid_enums_accepted,
     utf8_malformed_caught,
     utf8_wellformed_accepted,
     schema_load_test,
     schema_definitions_present,
     outbound_tools_list_validated].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

%%====================================================================
%% P6M5-6: Icon regression (handoff §1.3)
%%====================================================================

icon_buggy_shape_rejected(Config) ->
    _ = Config,
    BuggyIcon = #{<<"type">> => <<"emoji">>, <<"emoji">> => <<"star">>},
    {error, _} = erlmcp_schema:validate_protocol(<<"Icon">>, BuggyIcon).

icon_valid_data_uri_accepted(Config) ->
    _ = Config,
    ValidIcon = #{<<"src">> => <<"data:image/svg+xml;base64,PHN2Zz4=">>},
    ok = erlmcp_schema:validate_protocol(<<"Icon">>, ValidIcon).

icon_extra_fields_rejected(Config) ->
    _ = Config,
    IconWithExtras = #{<<"src">> => <<"data:image/png;base64,abc">>,
                       <<"emoji">> => <<"star">>},
    {error, _} = erlmcp_schema:validate_protocol(<<"Icon">>, IconWithExtras).

%%====================================================================
%% P6M5-7: taskSupport regression (handoff §1.5)
%%====================================================================

task_support_invalid_enum_rejected(Config) ->
    _ = Config,
    BadExec = #{<<"taskSupport">> => <<"allowed">>},
    {error, _} = erlmcp_schema:validate_protocol(<<"ToolExecution">>, BadExec).

task_support_valid_enums_accepted(Config) ->
    _ = Config,
    ok = erlmcp_schema:validate_protocol(<<"ToolExecution">>,
             #{<<"taskSupport">> => <<"forbidden">>}),
    ok = erlmcp_schema:validate_protocol(<<"ToolExecution">>,
             #{<<"taskSupport">> => <<"optional">>}),
    ok = erlmcp_schema:validate_protocol(<<"ToolExecution">>,
             #{<<"taskSupport">> => <<"required">>}).

%%====================================================================
%% P6M5-8: UTF-8 regression (handoff §1.4)
%%====================================================================

utf8_malformed_caught(Config) ->
    _ = Config,
    MalformedBin = <<"30", 16#B0, "C">>,
    {error, invalid_utf8} = erlmcp_codec:ensure_utf8(MalformedBin).

utf8_wellformed_accepted(Config) ->
    _ = Config,
    WellFormed = <<"30°C"/utf8>>,
    ok = erlmcp_codec:ensure_utf8(WellFormed).

%%====================================================================
%% P6M5-3: Schema load + digestion
%%====================================================================

schema_load_test(Config) ->
    _ = Config,
    {ok, Defs} = erlmcp_schema:load_protocol_schema(),
    ?assert(is_map(Defs)),
    ?assert(maps:size(Defs) >= 20).

schema_definitions_present(Config) ->
    _ = Config,
    Required = [<<"JSONRPCRequest">>, <<"JSONRPCNotification">>,
                <<"JSONRPCResultResponse">>, <<"JSONRPCErrorResponse">>,
                <<"Icon">>, <<"Tool">>, <<"ToolExecution">>,
                <<"Resource">>, <<"Prompt">>,
                <<"InitializeResult">>, <<"ListToolsResult">>,
                <<"CallToolResult">>],
    {ok, Defs} = erlmcp_schema:load_protocol_schema(),
    lists:foreach(fun(Name) ->
        ?assertMatch({ok, _}, maps:find(Name, Defs),
                     lists:flatten(io_lib:format("Missing: ~s", [Name])))
    end, Required).

%%====================================================================
%% P6M5-5: Outbound validation
%%====================================================================

outbound_tools_list_validated(Config) ->
    _ = Config,
    ValidResult = #{<<"tools">> =>
        [#{<<"name">> => <<"test">>,
           <<"inputSchema">> => #{<<"type">> => <<"object">>}}]},
    ValidMsg = #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => 1,
                 <<"result">> => ValidResult},
    ok = erlmcp_codec:validate_outbound(ValidMsg),

    BadToolResult = #{<<"tools">> =>
        [#{<<"name">> => <<"test">>,
           <<"inputSchema">> => #{<<"type">> => <<"object">>},
           <<"icons">> => [#{<<"emoji">> => <<"star">>}]}]},
    BadMsg = #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => 1,
               <<"result">> => BadToolResult},
    {error, _} = erlmcp_codec:validate_outbound(BadMsg).
