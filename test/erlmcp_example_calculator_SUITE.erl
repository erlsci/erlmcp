-module(erlmcp_example_calculator_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([
    tools_list/1,
    tool_call_add/1,
    tool_call_divide_by_zero/1,
    input_validation/1,
    structured_output/1,
    annotations_present/1,
    list_changed_on_add_remove/1,
    progress_reporting/1,
    discoverability_meta/1,
    directory_tool/1,
    instructions_generated/1,
    convert_tool/1
]).

all() ->
    [tools_list,
     tool_call_add,
     tool_call_divide_by_zero,
     input_validation,
     structured_output,
     annotations_present,
     list_changed_on_add_remove,
     progress_reporting,
     discoverability_meta,
     directory_tool,
     instructions_generated,
     convert_tool].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TC, Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"calculator-server">>, version => <<"1.0">>,
        handler => example_calculator_handler
    }),
    ok = erlmcp:add_tool(Srv, erlmcp:make_directory_tool()),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"calculator-server">>, version => <<"1.0">>
    }),
    initialize(Session),
    [{server, Session}, {srv, Srv} | Config].

end_per_testcase(_TC, Config) ->
    catch gen_statem:stop(?config(server, Config)),
    catch gen_server:stop(?config(srv, Config)),
    ok.

%%====================================================================
%% Helpers
%%====================================================================

initialize(Server) ->
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _ = wait_send(),
    ok.

wait_send() ->
    receive {send, Data} -> Data after 5000 -> error(transport_send_timeout) end.

decode(Json) ->
    {ok, Decoded} = erlmcp_codec:decode(Json),
    Decoded.

call_tool(Server, Name, Args) ->
    Id = erlang:unique_integer([positive]),
    CallReq = erlmcp_json_rpc:encode_request(Id, <<"tools/call">>, #{
        <<"name">> => Name, <<"arguments">> => Args
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    decode(wait_send()).

%%====================================================================
%% Tests
%%====================================================================

tools_list(Config) ->
    Server = ?config(server, Config),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq),
    Resp = decode(wait_send()),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp)),
    Names = lists:sort([maps:get(<<"name">>, T) || T <- Tools]),
    ?assert(lists:member(<<"add">>, Names)),
    ?assert(lists:member(<<"subtract">>, Names)),
    ?assert(lists:member(<<"multiply">>, Names)),
    ?assert(lists:member(<<"divide">>, Names)),
    ?assert(lists:member(<<"convert">>, Names)),
    ?assert(lists:member(<<"directory">>, Names)),
    ?assertEqual(6, length(Names)).

tool_call_add(Config) ->
    Server = ?config(server, Config),
    Resp = call_tool(Server, <<"add">>, #{<<"a">> => 10, <<"b">> => 32}),
    Result = maps:get(<<"result">>, Resp),
    ?assertMatch(#{<<"structuredContent">> := #{<<"result">> := 42}}, Result),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"42">>, maps:get(<<"text">>, Content)).

tool_call_divide_by_zero(Config) ->
    Server = ?config(server, Config),
    Resp = call_tool(Server, <<"divide">>, #{<<"a">> => 1, <<"b">> => 0}),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp).

input_validation(Config) ->
    Server = ?config(server, Config),
    Resp = call_tool(Server, <<"add">>, #{<<"a">> => 1}),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp).

structured_output(Config) ->
    Server = ?config(server, Config),
    Resp = call_tool(Server, <<"multiply">>, #{<<"a">> => 6, <<"b">> => 7}),
    Result = maps:get(<<"result">>, Resp),
    ?assertMatch(#{<<"structuredContent">> := #{<<"result">> := 42}}, Result).

annotations_present(Config) ->
    Server = ?config(server, Config),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq),
    Resp = decode(wait_send()),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp)),
    AddTool = hd([T || T <- Tools, maps:get(<<"name">>, T) =:= <<"add">>]),
    Ann = maps:get(<<"annotations">>, AddTool),
    ?assertEqual(true, maps:get(<<"readOnlyHint">>, Ann)).

list_changed_on_add_remove(Config) ->
    Srv = ?config(srv, Config),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"temp">>,
        description => <<"Temporary tool">>,
        input_schema => erlmcp_schema:object([]),
        category => <<"test">>,
        when_to_use => <<"Testing">>,
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    Notif1 = decode(wait_send()),
    ?assertEqual(<<"notifications/tools/list_changed">>,
                 maps:get(<<"method">>, Notif1)),
    ok = erlmcp:remove_tool(Srv, <<"temp">>),
    Notif2 = decode(wait_send()),
    ?assertEqual(<<"notifications/tools/list_changed">>,
                 maps:get(<<"method">>, Notif2)).

progress_reporting(Config) ->
    Server = ?config(server, Config),
    Srv = ?config(srv, Config),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"slow_add">>,
        description => <<"Slow addition with progress">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"a">>, erlmcp_schema:number(), [required]),
            erlmcp_schema:field(<<"b">>, erlmcp_schema:number(), [required])
        ]),
        category => <<"arithmetic">>,
        when_to_use => <<"Slow addition">>,
        handler => fun(#{<<"a">> := A, <<"b">> := B}, Ctx) ->
            erlmcp_ctx:report_progress(Ctx, 0.5, <<"computing">>),
            {ok, erlmcp:text(format_num(A + B))}
        end
    }),
    _ = wait_send(),
    Id = 100,
    CallReq = erlmcp_json_rpc:encode_request(Id, <<"tools/call">>, #{
        <<"name">> => <<"slow_add">>,
        <<"arguments">> => #{<<"a">> => 1, <<"b">> => 2},
        <<"_meta">> => #{<<"progressToken">> => <<"progress-1">>}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    ProgressNotif = decode(wait_send()),
    ?assertEqual(<<"notifications/progress">>,
                 maps:get(<<"method">>, ProgressNotif)),
    Params = maps:get(<<"params">>, ProgressNotif),
    ?assertEqual(<<"progress-1">>, maps:get(<<"progressToken">>, Params)),
    ToolResp = decode(wait_send()),
    ?assertMatch(#{<<"result">> := _}, ToolResp).

discoverability_meta(Config) ->
    Server = ?config(server, Config),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq),
    Resp = decode(wait_send()),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp)),
    AddTool = hd([T || T <- Tools, maps:get(<<"name">>, T) =:= <<"add">>]),
    Meta = maps:get(<<"_meta">>, AddTool),
    ?assertEqual(<<"arithmetic">>, maps:get(<<"io.erlmcp/category">>, Meta)),
    ?assert(is_binary(maps:get(<<"io.erlmcp/when_to_use">>, Meta))),
    ?assert(is_list(maps:get(<<"io.erlmcp/next">>, Meta))).

directory_tool(Config) ->
    Server = ?config(server, Config),
    Resp = call_tool(Server, <<"directory">>, #{}),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    DirJson = maps:get(<<"text">>, Content),
    {ok, DirMap} = erlmcp_codec:decode(DirJson),
    ToolsByCat = maps:get(<<"tools">>, DirMap),
    ?assert(maps:is_key(<<"arithmetic">>, ToolsByCat)),
    ArithTools = maps:get(<<"arithmetic">>, ToolsByCat),
    ArithNames = [maps:get(<<"name">>, T) || T <- ArithTools],
    ?assert(lists:member(<<"add">>, ArithNames)).

instructions_generated(Config) ->
    Server = ?config(server, Config),
    Instructions = erlmcp_server_session:get_instructions(Server),
    ?assert(is_binary(Instructions)),
    ?assert(binary:match(Instructions, <<"arithmetic">>) =/= nomatch),
    ?assert(binary:match(Instructions, <<"conversion">>) =/= nomatch).

convert_tool(Config) ->
    Server = ?config(server, Config),
    Resp = call_tool(Server, <<"convert">>,
        #{<<"value">> => 100, <<"from">> => <<"c">>, <<"to">> => <<"f">>}),
    Result = maps:get(<<"result">>, Resp),
    #{<<"result">> := FVal} = maps:get(<<"structuredContent">>, Result),
    ?assertEqual(212.0, FVal).

%%====================================================================
%% Internal
%%====================================================================

format_num(N) when is_integer(N) -> integer_to_binary(N);
format_num(N) when is_float(N) -> float_to_binary(N, [{decimals, 10}, compact]).
