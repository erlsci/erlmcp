-module(erlmcp_tools_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
    add_tool_and_call/1,
    handler_behaviour/1,
    input_validation_rejects/1,
    tools_list_shows_registered/1,
    tools_list_paginated/1,
    unknown_tool_error/1,
    tool_annotations_in_list/1,
    tools_list_changed_notification/1,
    capability_reflects_tools/1,
    output_schema_structured_content/1,
    output_schema_violation_caught/1,
    all_content_types/1,
    progress_notification/1
]).

all() ->
    [add_tool_and_call,
     handler_behaviour,
     input_validation_rejects,
     tools_list_shows_registered,
     tools_list_paginated,
     unknown_tool_error,
     tool_annotations_in_list,
     tools_list_changed_notification,
     capability_reflects_tools,
     output_schema_structured_content,
     output_schema_violation_caught,
     all_content_types,
     progress_notification].

init_per_testcase(_TC, Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test-server">>,
        version => <<"1.0">>
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test-server">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    [{server, Srv}, {session, Session} | Config].

end_per_testcase(_TC, Config) ->
    Session = ?config(session, Config),
    Srv = ?config(server, Config),
    case is_process_alive(Session) of
        true -> gen_statem:stop(Session);
        false -> ok
    end,
    case is_process_alive(Srv) of
        true -> gen_server:stop(Srv);
        false -> ok
    end,
    ok.

%%====================================================================
%% Helpers
%%====================================================================

initialize(Session) ->
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Session, InitReq),
    _InitResp = wait_send(),
    ok.

wait_send() ->
    receive {send, Data} -> Data after 5000 -> error(transport_send_timeout) end.

decode(Json) ->
    {ok, Decoded} = erlmcp_codec:decode(Json),
    Decoded.

%%====================================================================
%% M2a-2: add_tool/2 registers a tool and tools/call reaches the handler
%%====================================================================

add_tool_and_call(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"x">>, erlmcp_schema:number(), [required])
    ]),
    ok = erlmcp:add_tool(Server, #{
        name => <<"double">>,
        description => <<"Double a number">>,
        input_schema => Schema,
        handler => fun(#{<<"x">> := X}, _Ctx) ->
            {ok, erlmcp:text(list_to_binary(integer_to_list(trunc(X * 2))))}
        end
    }),
    initialize(Session),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"double">>,
        <<"arguments">> => #{<<"x">> => 21}
    }),
    erlmcp_server_session:send_message(Session, CallReq),
    Resp = decode(wait_send()),
    ?assertEqual(2, maps:get(<<"id">>, Resp)),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"text">>, maps:get(<<"type">>, Content)),
    ?assertEqual(<<"42">>, maps:get(<<"text">>, Content)).

%%====================================================================
%% M2a-3: handler behaviour module; xref-checkable, no apply/3
%%====================================================================

handler_behaviour(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    ok = erlmcp:register_handler(Server, test_calc_handler),
    initialize(Session),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"add">>,
        <<"arguments">> => #{<<"a">> => 3, <<"b">> => 4}
    }),
    erlmcp_server_session:send_message(Session, CallReq),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"7">>, maps:get(<<"text">>, Content)).

%%====================================================================
%% M2a-6: invalid args → -32602 and handler never runs
%%====================================================================

input_validation_rejects(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"name">>, erlmcp_schema:string(), [required])
    ]),
    Ref = make_ref(),
    TestPid = self(),
    ok = erlmcp:add_tool(Server, #{
        name => <<"greet">>,
        description => <<"Greet by name">>,
        input_schema => Schema,
        handler => fun(_, _) ->
            TestPid ! {handler_called, Ref},
            {ok, erlmcp:text(<<"hi">>)}
        end
    }),
    initialize(Session),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"greet">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Session, CallReq),
    Resp = decode(wait_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp),
    receive {handler_called, Ref} -> ct:fail(handler_should_not_run)
    after 200 -> ok
    end.

%%====================================================================
%% M2a-4 (partial): tools/list returns registered tools
%%====================================================================

tools_list_shows_registered(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"foo">>,
        description => <<"Foo tool">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    initialize(Session),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Session, ListReq),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    Tools = maps:get(<<"tools">>, Result),
    ?assertEqual(1, length(Tools)),
    [Tool] = Tools,
    ?assertEqual(<<"foo">>, maps:get(<<"name">>, Tool)),
    ?assertEqual(<<"Foo tool">>, maps:get(<<"description">>, Tool)).

%%====================================================================
%% tools/call with unknown tool → error
%%====================================================================

unknown_tool_error(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    initialize(Session),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"nonexistent">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Session, CallReq),
    Resp = decode(wait_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp).

%%====================================================================
%% M2a-9: annotations settable and surfaced in tools/list
%%====================================================================

tool_annotations_in_list(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"safe">>,
        description => <<"A safe tool">>,
        input_schema => erlmcp_schema:object([]),
        annotations => #{readOnlyHint => true, title => <<"Safe Tool">>},
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    initialize(Session),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Session, ListReq),
    Resp = decode(wait_send()),
    [Tool] = maps:get(<<"tools">>, maps:get(<<"result">>, Resp)),
    Ann = maps:get(<<"annotations">>, Tool),
    ?assertEqual(true, maps:get(<<"readOnlyHint">>, Ann)),
    ?assertEqual(<<"Safe Tool">>, maps:get(<<"title">>, Ann)).

%%====================================================================
%% M2a-10: runtime add/remove → notifications/tools/list_changed
%%====================================================================

tools_list_changed_notification(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    initialize(Session),
    ok = erlmcp:add_tool(Server, #{
        name => <<"dynamic">>,
        description => <<"Added at runtime">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    AddNotif = decode(wait_send()),
    ?assertEqual(<<"notifications/tools/list_changed">>,
                 maps:get(<<"method">>, AddNotif)),
    ok = erlmcp:remove_tool(Server, <<"dynamic">>),
    RemoveNotif = decode(wait_send()),
    ?assertEqual(<<"notifications/tools/list_changed">>,
                 maps:get(<<"method">>, RemoveNotif)).

%%====================================================================
%% M2a-4: paginated tools/list round-trips with opaque cursor
%%====================================================================

tools_list_paginated(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    lists:foreach(fun(N) ->
        Name = list_to_binary("tool_" ++ integer_to_list(N)),
        ok = erlmcp:add_tool(Server, #{
            name => Name,
            description => <<"Tool ", Name/binary>>,
            input_schema => erlmcp_schema:object([]),
            handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
        })
    end, lists:seq(1, 3)),
    initialize(Session),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Session, ListReq),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    Tools = maps:get(<<"tools">>, Result),
    ?assertEqual(3, length(Tools)),
    ?assertNot(maps:is_key(<<"nextCursor">>, Result)).

%%====================================================================
%% M2a-7: output schema + structuredContent
%%====================================================================

output_schema_structured_content(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    OutSchema = erlmcp_schema:object([
        erlmcp_schema:field(<<"sum">>, erlmcp_schema:number(), [required])
    ]),
    ok = erlmcp:add_tool(Server, #{
        name => <<"add_structured">>,
        description => <<"Add with structured output">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"a">>, erlmcp_schema:number(), [required]),
            erlmcp_schema:field(<<"b">>, erlmcp_schema:number(), [required])
        ]),
        output_schema => OutSchema,
        handler => fun(#{<<"a">> := A, <<"b">> := B}, _Ctx) ->
            Sum = A + B,
            {ok, erlmcp:text(list_to_binary(io_lib:format("~p", [Sum]))),
                 #{<<"sum">> => Sum}}
        end
    }),
    initialize(Session),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"add_structured">>,
        <<"arguments">> => #{<<"a">> => 3, <<"b">> => 4}
    }),
    erlmcp_server_session:send_message(Session, CallReq),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    ?assertMatch(#{<<"structuredContent">> := #{<<"sum">> := 7}}, Result),
    ?assert(is_list(maps:get(<<"content">>, Result))).

output_schema_violation_caught(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    OutSchema = erlmcp_schema:object([
        erlmcp_schema:field(<<"value">>, erlmcp_schema:string(), [required])
    ]),
    ok = erlmcp:add_tool(Server, #{
        name => <<"bad_output">>,
        description => <<"Returns invalid structured output">>,
        input_schema => erlmcp_schema:object([]),
        output_schema => OutSchema,
        handler => fun(_, _) ->
            {ok, erlmcp:text(<<"oops">>), #{<<"wrong_key">> => 42}}
        end
    }),
    initialize(Session),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"bad_output">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Session, CallReq),
    Resp = decode(wait_send()),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32603}}, Resp).

%%====================================================================
%% M2a-8: all five content types round-trip through tools/call
%%====================================================================

all_content_types(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"content_types">>,
        description => <<"Returns all content types">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) ->
            {ok, [
                erlmcp:text(<<"hello">>),
                erlmcp:image(<<"aW1n">>, <<"image/png">>),
                erlmcp:audio(<<"YXVk">>, <<"audio/wav">>),
                erlmcp:embedded_resource(#{<<"uri">> => <<"file:///a.txt">>,
                                           <<"text">> => <<"content">>}),
                erlmcp:resource_link(<<"file:///b.txt">>, <<"text/plain">>)
            ]}
        end
    }),
    initialize(Session),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"content_types">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Session, CallReq),
    Resp = decode(wait_send()),
    Content = maps:get(<<"content">>, maps:get(<<"result">>, Resp)),
    ?assertEqual(5, length(Content)),
    [T, I, A, E, R] = Content,
    ?assertEqual(<<"text">>, maps:get(<<"type">>, T)),
    ?assertEqual(<<"image">>, maps:get(<<"type">>, I)),
    ?assertEqual(<<"audio">>, maps:get(<<"type">>, A)),
    ?assertEqual(<<"resource">>, maps:get(<<"type">>, E)),
    ?assertEqual(<<"resource_link">>, maps:get(<<"type">>, R)).

%%====================================================================
%% M2a-11: progress notification via erlmcp_ctx:report_progress/3
%%====================================================================

progress_notification(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"slow">>,
        description => <<"Reports progress">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            erlmcp_ctx:report_progress(Ctx, 0.5, <<"halfway">>),
            {ok, erlmcp:text(<<"done">>)}
        end
    }),
    initialize(Session),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"slow">>,
        <<"arguments">> => #{},
        <<"_meta">> => #{<<"progressToken">> => <<"tok1">>}
    }),
    erlmcp_server_session:send_message(Session, CallReq),
    ProgressNotif = decode(wait_send()),
    ?assertEqual(<<"notifications/progress">>,
                 maps:get(<<"method">>, ProgressNotif)),
    ProgressParams = maps:get(<<"params">>, ProgressNotif),
    ?assertEqual(<<"tok1">>, maps:get(<<"progressToken">>, ProgressParams)),
    ?assertEqual(0.5, maps:get(<<"progress">>, ProgressParams)),
    ToolResp = decode(wait_send()),
    ?assertMatch(#{<<"result">> := #{<<"content">> := _}}, ToolResp).

%%====================================================================
%% M2a-12: capability map advertises tools only when registered
%%====================================================================

capability_reflects_tools(Config) ->
    Server = ?config(server, Config),
    Session = ?config(session, Config),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Session, InitReq),
    Resp1 = decode(wait_send()),
    Caps1 = maps:get(<<"capabilities">>, maps:get(<<"result">>, Resp1)),
    ?assertNot(maps:is_key(<<"tools">>, Caps1)),
    gen_statem:stop(Session),
    gen_server:stop(Server),

    {ok, Srv2} = erlmcp_server:start_link(#{
        name => <<"test-server-2">>,
        version => <<"1.0">>,
        tools => [#{name => <<"t">>, description => <<"t">>,
                    input_schema => erlmcp_schema:object([]),
                    handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end}]
    }),
    Responder2 = erlmcp_reply:new_device(self()),
    {ok, Session2} = erlmcp_server_session:start_link(#{
        server => Srv2, responder => Responder2,
        name => <<"test-server-2">>, version => <<"1.0">>
    }),
    erlmcp_server_session:send_message(Session2, InitReq),
    Resp2 = decode(wait_send()),
    Caps2 = maps:get(<<"capabilities">>, maps:get(<<"result">>, Resp2)),
    ?assert(maps:is_key(<<"tools">>, Caps2)),
    ToolsCap = maps:get(<<"tools">>, Caps2),
    ?assertEqual(true, maps:get(<<"listChanged">>, ToolsCap)),
    gen_statem:stop(Session2),
    gen_server:stop(Srv2).
