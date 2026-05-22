-module(erlmcp_conformance).

-export([run_server_scorecard/0]).

-define(SCENARIOS, [
    %% L0 — protocol basics
    {l0, <<"initialize">>, fun scenario_initialize/1},
    {l0, <<"ping">>, fun scenario_ping/1},
    {l0, <<"version_negotiation">>, fun scenario_version_negotiation/1},
    {l0, <<"pre_init_rejected">>, fun scenario_pre_init_rejected/1},
    %% L1 — tools
    {l1, <<"tools/list">>, fun scenario_tools_list/1},
    {l1, <<"tools/call">>, fun scenario_tools_call/1},
    {l1, <<"tools/call_validation">>, fun scenario_tools_call_validation/1},
    {l1, <<"tools/annotations">>, fun scenario_tools_annotations/1},
    %% L2 — resources
    {l2, <<"resources/list">>, fun scenario_resources_list/1},
    {l2, <<"resources/read">>, fun scenario_resources_read/1},
    {l2, <<"resources/templates">>, fun scenario_resources_templates/1},
    {l2, <<"resources/subscribe">>, fun scenario_resources_subscribe/1},
    %% L3 — prompts + logging
    {l3, <<"prompts/list">>, fun scenario_prompts_list/1},
    {l3, <<"prompts/get">>, fun scenario_prompts_get/1},
    {l3, <<"logging/setLevel">>, fun scenario_logging_set_level/1},
    {l3, <<"logging/filter">>, fun scenario_logging_filter/1},
    %% L4 — completion + notifications + capabilities
    {l4, <<"completion/complete">>, fun scenario_completion/1},
    {l4, <<"capabilities_derived">>, fun scenario_capabilities_derived/1},
    {l4, <<"tools/list_changed">>, fun scenario_tools_list_changed/1},
    {l4, <<"resources/list_changed">>, fun scenario_resources_list_changed/1},
    {l4, <<"prompts/list_changed">>, fun scenario_prompts_list_changed/1},
    {l4, <<"worker_crash_isolation">>, fun scenario_worker_crash_isolation/1},
    {l4, <<"cancellation">>, fun scenario_cancellation/1},
    {l4, <<"structured_output">>, fun scenario_structured_output/1}
]).

-spec run_server_scorecard() -> {float(), [{atom(), binary(), pass | fail}]}.
run_server_scorecard() ->
    Server = setup_conformance_server(),
    Results = lists:map(fun({Level, Name, ScenarioFun}) ->
        try ScenarioFun(Server) of
            pass -> {Level, Name, pass};
            fail -> {Level, Name, fail}
        catch _:_ ->
            {Level, Name, fail}
        end
    end, ?SCENARIOS),
    gen_statem:stop(Server),
    Passed = length([ok || {_, _, pass} <- Results]),
    Total = length(Results),
    Score = (Passed / Total) * 100,
    {Score, Results}.

%%====================================================================
%% Server setup — registers tools, resources, prompts
%%====================================================================

setup_conformance_server() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => self(),
        name => <<"conformance-server">>,
        version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp_server_session:register_tool(Server, #{
        name => <<"echo">>,
        description => <<"Echo input">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"msg">>, erlmcp_schema:string(), [required])
        ]),
        output_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"echo">>, erlmcp_schema:string(), [required])
        ]),
        annotations => #{readOnlyHint => true},
        handler => fun(#{<<"msg">> := Msg}, _Ctx) ->
            {ok, erlmcp:text(Msg), #{<<"echo">> => Msg}}
        end
    }),
    ok = erlmcp_server_session:register_tool(Server, #{
        name => <<"crash_tool">>,
        description => <<"Always crashes">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> error(intentional_crash) end
    }),
    ok = erlmcp_server_session:register_tool(Server, #{
        name => <<"slow_tool">>,
        description => <<"Slow tool for cancellation testing">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> receive after 10000 -> {ok, erlmcp:text(<<"done">>)} end end
    }),
    ok = erlmcp_server_session:register_resource(Server, #{
        uri => <<"conf://data/1">>,
        name => <<"Data 1">>,
        description => <<"Test resource">>,
        mime_type => <<"text/plain">>,
        handler => fun(_Ctx) -> {ok, #{<<"uri">> => <<"conf://data/1">>,
                                       <<"text">> => <<"resource content">>}} end
    }),
    ok = erlmcp_server_session:register_resource_template(Server, #{
        uri_template => <<"conf://data/{id}">>,
        name => <<"Data item">>,
        handler => fun(#{<<"id">> := Id}, _Ctx) ->
            {ok, #{<<"uri">> => <<"conf://data/", Id/binary>>,
                   <<"text">> => <<"item ", Id/binary>>}}
        end,
        completions => #{<<"id">> => fun(_) -> [<<"1">>, <<"2">>, <<"3">>] end}
    }),
    ok = erlmcp_server_session:register_prompt(Server, #{
        name => <<"summarize">>,
        description => <<"Summarize text">>,
        arguments => [#{name => <<"text">>, description => <<"Text to summarize">>, required => true}],
        handler => fun(#{<<"text">> := Text}, _) ->
            {ok, [#{<<"role">> => <<"user">>,
                    <<"content">> => #{<<"type">> => <<"text">>,
                                       <<"text">> => <<"Summarize: ", Text/binary>>}}]}
        end,
        completions => #{<<"text">> => fun(_) -> [<<"sample text">>] end}
    }),
    Server.

%%====================================================================
%% L0 scenarios — protocol basics
%%====================================================================

scenario_initialize(Server) ->
    Resp = send_req(Server, 1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    Result = maps:get(<<"result">>, Resp),
    case maps:is_key(<<"protocolVersion">>, Result)
         andalso maps:is_key(<<"capabilities">>, Result)
         andalso maps:is_key(<<"serverInfo">>, Result) of
        true -> pass;
        false -> fail
    end.

scenario_ping(Server) ->
    Resp = send_req(Server, 2, <<"ping">>, #{}),
    case maps:is_key(<<"result">>, Resp) of
        true -> pass;
        false -> fail
    end.

scenario_version_negotiation(_Server) ->
    {ok, S2} = erlmcp_server_session:start_link(#{
        transport => self(), name => <<"t">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    Resp = send_req(S2, 1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"1999-01-01">>,
        <<"capabilities">> => #{}
    }),
    gen_statem:stop(S2),
    case maps:is_key(<<"error">>, Resp) of
        true -> pass;
        false -> fail
    end.

scenario_pre_init_rejected(_Server) ->
    {ok, S2} = erlmcp_server_session:start_link(#{
        transport => self(), name => <<"t">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    Resp = send_req(S2, 1, <<"ping">>, #{}),
    gen_statem:stop(S2),
    case maps:is_key(<<"error">>, Resp) of
        true -> pass;
        false -> fail
    end.

%%====================================================================
%% L1 scenarios — tools
%%====================================================================

scenario_tools_list(Server) ->
    Resp = send_req(Server, 3, <<"tools/list">>, #{}),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp, #{}), []),
    case length(Tools) >= 1 of
        true -> pass;
        false -> fail
    end.

scenario_tools_call(Server) ->
    Resp = send_req(Server, 4, <<"tools/call">>, #{
        <<"name">> => <<"echo">>,
        <<"arguments">> => #{<<"msg">> => <<"hello">>}
    }),
    case maps:is_key(<<"result">>, Resp) of
        true -> pass;
        false -> fail
    end.

scenario_tools_call_validation(Server) ->
    Resp = send_req(Server, 5, <<"tools/call">>, #{
        <<"name">> => <<"echo">>,
        <<"arguments">> => #{}
    }),
    case maps:get(<<"code">>, maps:get(<<"error">>, Resp, #{}), 0) of
        -32602 -> pass;
        _ -> fail
    end.

scenario_tools_annotations(Server) ->
    Resp = send_req(Server, 6, <<"tools/list">>, #{}),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp, #{}), []),
    Echo = hd([T || T <- Tools, maps:get(<<"name">>, T) =:= <<"echo">>]),
    case maps:is_key(<<"annotations">>, Echo) of
        true -> pass;
        false -> fail
    end.

%%====================================================================
%% L2 scenarios — resources
%%====================================================================

scenario_resources_list(Server) ->
    Resp = send_req(Server, 7, <<"resources/list">>, #{}),
    Resources = maps:get(<<"resources">>, maps:get(<<"result">>, Resp, #{}), []),
    case length(Resources) >= 1 of
        true -> pass;
        false -> fail
    end.

scenario_resources_read(Server) ->
    Resp = send_req(Server, 8, <<"resources/read">>,
                    #{<<"uri">> => <<"conf://data/1">>}),
    case maps:is_key(<<"result">>, Resp) of
        true ->
            Contents = maps:get(<<"contents">>, maps:get(<<"result">>, Resp), []),
            case length(Contents) >= 1 of true -> pass; false -> fail end;
        false -> fail
    end.

scenario_resources_templates(Server) ->
    Resp = send_req(Server, 9, <<"resources/templates/list">>, #{}),
    Tpls = maps:get(<<"resourceTemplates">>, maps:get(<<"result">>, Resp, #{}), []),
    case length(Tpls) >= 1 of
        true ->
            ReadResp = send_req(Server, 10, <<"resources/read">>,
                                #{<<"uri">> => <<"conf://data/99">>}),
            case maps:is_key(<<"result">>, ReadResp) of
                true -> pass;
                false -> fail
            end;
        false -> fail
    end.

scenario_resources_subscribe(Server) ->
    _ = send_req(Server, 11, <<"resources/subscribe">>,
                 #{<<"uri">> => <<"conf://data/1">>}),
    erlmcp_server_session:notify_resource_updated(Server, <<"conf://data/1">>),
    Notif = decode(wait_send()),
    _ = send_req(Server, 12, <<"resources/unsubscribe">>,
                 #{<<"uri">> => <<"conf://data/1">>}),
    case maps:get(<<"method">>, Notif, <<>>) of
        <<"notifications/resources/updated">> -> pass;
        _ -> fail
    end.

%%====================================================================
%% L3 scenarios — prompts + logging
%%====================================================================

scenario_prompts_list(Server) ->
    Resp = send_req(Server, 13, <<"prompts/list">>, #{}),
    Prompts = maps:get(<<"prompts">>, maps:get(<<"result">>, Resp, #{}), []),
    case length(Prompts) >= 1 of
        true -> pass;
        false -> fail
    end.

scenario_prompts_get(Server) ->
    Resp = send_req(Server, 14, <<"prompts/get">>,
                    #{<<"name">> => <<"summarize">>,
                      <<"arguments">> => #{<<"text">> => <<"test">>}}),
    case maps:is_key(<<"result">>, Resp) of
        true ->
            Msgs = maps:get(<<"messages">>,
                            maps:get(<<"result">>, Resp), []),
            case length(Msgs) >= 1 of true -> pass; false -> fail end;
        false -> fail
    end.

scenario_logging_set_level(Server) ->
    Resp = send_req(Server, 15, <<"logging/setLevel">>,
                    #{<<"level">> => <<"info">>}),
    case maps:is_key(<<"result">>, Resp) of
        true -> pass;
        false -> fail
    end.

scenario_logging_filter(Server) ->
    _ = send_req(Server, 16, <<"logging/setLevel">>,
                 #{<<"level">> => <<"error">>}),
    erlmcp_server_session:emit_log(Server, debug, <<"t">>, <<"no">>),
    receive {send, _} -> fail after 100 -> ok end,
    erlmcp_server_session:emit_log(Server, error, <<"t">>, <<"yes">>),
    Notif = decode(wait_send()),
    case maps:get(<<"method">>, Notif, <<>>) of
        <<"notifications/message">> -> pass;
        _ -> fail
    end.

%%====================================================================
%% L4 scenarios — completion, notifications, capabilities
%%====================================================================

scenario_completion(Server) ->
    Resp = send_req(Server, 17, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"summarize">>},
        <<"argument">> => #{<<"name">> => <<"text">>, <<"value">> => <<"">>}
    }),
    Completion = maps:get(<<"completion">>,
                          maps:get(<<"result">>, Resp, #{}), #{}),
    case maps:get(<<"values">>, Completion, []) of
        Vals when length(Vals) >= 1 -> pass;
        _ -> fail
    end.

scenario_capabilities_derived(_Server) ->
    {ok, S2} = erlmcp_server_session:start_link(#{
        transport => self(), name => <<"t">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp_server_session:register_tool(S2, #{
        name => <<"t">>, description => <<"t">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    ok = erlmcp_server_session:register_resource(S2, #{
        uri => <<"x://a">>, name => <<"A">>,
        handler => fun(_) -> {ok, #{<<"uri">> => <<"x://a">>, <<"text">> => <<"t">>}} end
    }),
    ok = erlmcp_server_session:register_prompt(S2, #{
        name => <<"p">>, description => <<"P">>,
        handler => fun(_, _) -> {ok, []} end
    }),
    Resp = send_req(S2, 1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    gen_statem:stop(S2),
    Caps = maps:get(<<"capabilities">>,
                    maps:get(<<"result">>, Resp, #{}), #{}),
    case maps:is_key(<<"tools">>, Caps)
         andalso maps:is_key(<<"resources">>, Caps)
         andalso maps:is_key(<<"prompts">>, Caps)
         andalso maps:is_key(<<"logging">>, Caps)
         andalso maps:is_key(<<"completions">>, Caps) of
        true -> pass;
        false -> fail
    end.

scenario_tools_list_changed(Server) ->
    ok = erlmcp_server_session:register_tool(Server, #{
        name => <<"tmp_tool">>, description => <<"Tmp">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    Notif = decode(wait_send()),
    ok = erlmcp_server_session:unregister_tool(Server, <<"tmp_tool">>),
    _ = wait_send(),
    case maps:get(<<"method">>, Notif, <<>>) of
        <<"notifications/tools/list_changed">> -> pass;
        _ -> fail
    end.

scenario_resources_list_changed(Server) ->
    ok = erlmcp_server_session:register_resource(Server, #{
        uri => <<"tmp://r">>, name => <<"Tmp">>,
        handler => fun(_) -> {ok, #{<<"uri">> => <<"tmp://r">>, <<"text">> => <<"t">>}} end
    }),
    Notif = decode(wait_send()),
    ok = erlmcp_server_session:unregister_resource(Server, <<"tmp://r">>),
    _ = wait_send(),
    case maps:get(<<"method">>, Notif, <<>>) of
        <<"notifications/resources/list_changed">> -> pass;
        _ -> fail
    end.

scenario_prompts_list_changed(Server) ->
    ok = erlmcp_server_session:register_prompt(Server, #{
        name => <<"tmp_prompt">>, description => <<"Tmp">>,
        handler => fun(_, _) -> {ok, []} end
    }),
    Notif = decode(wait_send()),
    ok = erlmcp_server_session:unregister_prompt(Server, <<"tmp_prompt">>),
    _ = wait_send(),
    case maps:get(<<"method">>, Notif, <<>>) of
        <<"notifications/prompts/list_changed">> -> pass;
        _ -> fail
    end.

scenario_worker_crash_isolation(Server) ->
    Resp = send_req(Server, 20, <<"tools/call">>, #{
        <<"name">> => <<"crash_tool">>,
        <<"arguments">> => #{}
    }),
    case maps:get(<<"code">>, maps:get(<<"error">>, Resp, #{}), 0) of
        -32603 ->
            case is_process_alive(Server) of
                true -> pass;
                false -> fail
            end;
        _ -> fail
    end.

scenario_cancellation(Server) ->
    CallReq = erlmcp_json_rpc:encode_request(21, <<"tools/call">>, #{
        <<"name">> => <<"slow_tool">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    timer:sleep(50),
    CancelNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/cancelled">>, #{<<"requestId">> => 21}),
    erlmcp_server_session:send_message(Server, CancelNotif),
    timer:sleep(100),
    case is_process_alive(Server) of
        true -> pass;
        false -> fail
    end.

scenario_structured_output(Server) ->
    Resp = send_req(Server, 22, <<"tools/call">>, #{
        <<"name">> => <<"echo">>,
        <<"arguments">> => #{<<"msg">> => <<"test">>}
    }),
    Result = maps:get(<<"result">>, Resp, #{}),
    case maps:is_key(<<"structuredContent">>, Result)
         andalso maps:is_key(<<"content">>, Result) of
        true -> pass;
        false -> fail
    end.

%%====================================================================
%% Helpers
%%====================================================================

send_req(Server, Id, Method, Params) ->
    Req = erlmcp_json_rpc:encode_request(Id, Method, Params),
    erlmcp_server_session:send_message(Server, Req),
    decode(wait_send()).

decode(Json) ->
    {ok, D} = erlmcp_codec:decode(Json), D.

wait_send() ->
    receive {send, Data} -> Data after 5000 -> error(transport_send_timeout) end.
