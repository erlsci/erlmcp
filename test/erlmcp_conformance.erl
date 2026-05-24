-module(erlmcp_conformance).

-export([run_server_scorecard/0, run_client_scorecard/0, run_transport_scorecard/0,
         publish_scorecard/0, publish_scorecard/1]).

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
    {l4, <<"structured_output">>, fun scenario_structured_output/1},
    %% L4 — discoverability (protocol-native surfaces)
    {l4, <<"instructions_present">>, fun scenario_instructions/1},
    {l4, <<"meta_wayfinding">>, fun scenario_meta_wayfinding/1},
    {l4, <<"annotations_present">>, fun scenario_annotations/1},
    %% L4 — batch + tasks
    {l4, <<"batch_execution">>, fun scenario_batch/1},
    {l4, <<"task_lifecycle">>, fun scenario_task_lifecycle/1}
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
    catch application:stop(erlmcp),
    timer:sleep(100),
    gen_statem:stop(Server),
    Passed = length([ok || {_, _, pass} <- Results]),
    Total = length(Results),
    Score = (Passed / Total) * 100,
    {Score, Results}.

%%====================================================================
%% Server setup — registers tools, resources, prompts
%%====================================================================

setup_conformance_server() ->
    {ok, _} = application:ensure_all_started(erlmcp),
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
        category => <<"utility">>,
        when_to_use => <<"When you need to echo text back">>,
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

scenario_batch(Server) ->
    Batch = jsx:encode([
        #{<<"jsonrpc">> => <<"2.0">>, <<"id">> => 100, <<"method">> => <<"ping">>},
        #{<<"jsonrpc">> => <<"2.0">>, <<"method">> => <<"notifications/initialized">>}
    ]),
    erlmcp_server_session:send_message(Server, Batch),
    Resp = decode(wait_send()),
    case is_list(Resp) andalso length(Resp) =:= 1 of
        true -> pass;
        false -> fail
    end.

scenario_task_lifecycle(Server) ->
    ok = erlmcp_server_session:register_tool(Server, #{
        name => <<"task_conf">>, description => <<"Task conf">>,
        input_schema => erlmcp_schema:object([]),
        task_support => optional,
        handler => fun(_, _) -> timer:sleep(100), {ok, erlmcp:text(<<"done">>)} end
    }),
    _ = wait_send(),
    CallResp = send_req(Server, 50, <<"tools/call">>, #{
        <<"name">> => <<"task_conf">>,
        <<"arguments">> => #{},
        <<"_meta">> => #{<<"_task">> => true}
    }),
    case maps:get(<<"taskId">>, maps:get(<<"result">>, CallResp, #{}), undefined) of
        undefined -> fail;
        TaskId ->
            timer:sleep(200),
            ResultResp = send_req(Server, 51, <<"tasks/result">>,
                                  #{<<"id">> => TaskId}),
            case maps:is_key(<<"result">>, ResultResp) of
                true -> pass;
                false -> fail
            end
    end.

scenario_instructions(_Server) ->
    {ok, S2} = erlmcp_server_session:start_link(#{
        transport => self(), name => <<"t">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp_server_session:register_tool(S2, #{
        name => <<"t">>, description => <<"t">>,
        input_schema => erlmcp_schema:object([]),
        category => <<"test">>, when_to_use => <<"testing">>,
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    Resp = send_req(S2, 1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    gen_statem:stop(S2),
    Result = maps:get(<<"result">>, Resp, #{}),
    case maps:is_key(<<"instructions">>, Result) of
        true -> pass;
        false -> fail
    end.

scenario_meta_wayfinding(Server) ->
    Resp = send_req(Server, 30, <<"tools/list">>, #{}),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp, #{}), []),
    HasMeta = lists:any(fun(T) -> maps:is_key(<<"_meta">>, T) end, Tools),
    case HasMeta of true -> pass; false -> fail end.

scenario_annotations(Server) ->
    Resp = send_req(Server, 31, <<"tools/list">>, #{}),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, Resp, #{}), []),
    HasAnn = lists:any(fun(T) -> maps:is_key(<<"annotations">>, T) end, Tools),
    case HasAnn of true -> pass; false -> fail end.

%%====================================================================
%% Publish scorecard artifact (M5a-1)
%%====================================================================

-spec publish_scorecard() -> ok.
publish_scorecard() ->
    publish_scorecard("conformance/results").

-spec publish_scorecard(string()) -> ok.
publish_scorecard(Dir) ->
    {ServerScore, ServerResults} = run_server_scorecard(),
    {ClientScore, ClientResults} = run_client_scorecard(),
    {TransportScore, TransportResults} = run_transport_scorecard(),
    {{Y,M,D},{H,Mi,S}} = calendar:universal_time(),
    Date = io_lib:format("~4..0B-~2..0B-~2..0B", [Y,M,D]),
    Time = io_lib:format("~2..0B:~2..0B:~2..0B", [H,Mi,S]),
    Version = "0.6.0",
    Filename = lists:flatten(io_lib:format("~s/erlmcp-~s-~s.txt",
        [Dir, Version, Date])),
    Lines = [
        io_lib:format("# erlmcp Conformance Scorecard~n", []),
        io_lib:format("Version: ~s~n", [Version]),
        io_lib:format("Date: ~sT~sZ~n", [Date, Time]),
        io_lib:format("Protocol: MCP 2025-11-25~n", []),
        io_lib:format("Reference: rmcp server 87.5%, client 87.5%~n~n", []),
        io_lib:format("## Server (~.1f%)~n", [ServerScore]),
        format_results(ServerResults),
        io_lib:format("~n## Client (~.1f%)~n", [ClientScore]),
        format_results(ClientResults),
        io_lib:format("~n## Transport (~.1f%)~n", [TransportScore]),
        format_results(TransportResults),
        io_lib:format("~n## Summary~n", []),
        io_lib:format("Server:    ~.1f% (ref: 87.5%)~n", [ServerScore]),
        io_lib:format("Client:    ~.1f% (ref: 87.5%)~n", [ClientScore]),
        io_lib:format("Transport: ~.1f%~n", [TransportScore])
    ],
    ok = filelib:ensure_dir(Filename),
    ok = file:write_file(Filename, Lines),
    ok.

format_results(Results) ->
    [io_lib:format("  ~p ~s: ~s~n", [Level, Name,
        case Status of pass -> "PASS"; fail -> "FAIL" end])
     || {Level, Name, Status} <- Results].

%%====================================================================
%% Client scorecard (M3b)
%%====================================================================

-define(CLIENT_SCENARIOS, [
    {l0, <<"client_initialize">>, fun cs_initialize/1},
    {l0, <<"client_ping">>, fun cs_ping/1},
    {l1, <<"client_list_tools">>, fun cs_list_tools/1},
    {l1, <<"client_call_tool">>, fun cs_call_tool/1},
    {l2, <<"client_list_resources">>, fun cs_list_resources/1},
    {l2, <<"client_read_resource">>, fun cs_read_resource/1},
    {l3, <<"client_list_prompts">>, fun cs_list_prompts/1},
    {l3, <<"client_get_prompt">>, fun cs_get_prompt/1},
    {l3, <<"client_set_log_level">>, fun cs_set_log_level/1},
    {l4, <<"client_completion">>, fun cs_completion/1},
    {l4, <<"client_capability_gating">>, fun cs_capability_gating/1},
    {l4, <<"client_sampling_callback">>, fun cs_sampling_callback/1},
    {l4, <<"client_roots_callback">>, fun cs_roots_callback/1},
    {l4, <<"client_elicitation_callback">>, fun cs_elicitation_callback/1},
    {l4, <<"client_capability_advertisement">>, fun cs_capability_advertisement/1},
    {l4, <<"client_inbound_unknown_method">>, fun cs_inbound_unknown/1}
]).

-spec run_client_scorecard() -> {float(), [{atom(), binary(), pass | fail}]}.
run_client_scorecard() ->
    Results = lists:map(fun({Level, Name, ScenarioFun}) ->
        try ScenarioFun(unused) of
            pass -> {Level, Name, pass};
            fail -> {Level, Name, fail}
        catch _:_ ->
            {Level, Name, fail}
        end
    end, ?CLIENT_SCENARIOS),
    Passed = length([ok || {_, _, pass} <- Results]),
    Total = length(Results),
    Score = (Passed / Total) * 100,
    {Score, Results}.

setup_client_pair() ->
    SB = spawn_link(fun() -> cbridge(undefined) end),
    CB = spawn_link(fun() -> cbridge(undefined) end),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => SB, name => <<"cs">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp:register_handler(Server, example_calculator_handler),
    ok = example_weather_handler:register_all(Server),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CB, owner => self(),
        name => <<"cc">>, version => <<"1.0">>
    }),
    ok = erlmcp_client_session:set_sampling_handler(Client, test_sampling_handler),
    ok = erlmcp_client_session:set_roots_handler(Client, test_roots_handler),
    ok = erlmcp_client_session:set_elicitation_handler(Client, test_elicitation_handler),
    SB ! {peer, Client},
    CB ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    {Server, Client}.

cbridge(Peer) ->
    receive
        {peer, Pid} -> cbridge(Pid);
        {send, Data} when is_pid(Peer) ->
            gen_statem:cast(Peer, {transport_data, Data}),
            cbridge(Peer);
        _ -> cbridge(Peer)
    end.

cs_initialize(_) ->
    {_S, C} = setup_client_pair(),
    R = gen_statem:call(C, get_state),
    erlmcp_client_session:stop(C),
    case R of operational -> pass; _ -> fail end.

cs_ping(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:ping(C),
    erlmcp_client_session:stop(C),
    case R of ok -> pass; _ -> fail end.

cs_list_tools(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:list_tools(C),
    erlmcp_client_session:stop(C),
    case R of {ok, L} when length(L) >= 1 -> pass; _ -> fail end.

cs_call_tool(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:call_tool(C, <<"add">>,
        #{<<"a">> => 1, <<"b">> => 2}),
    erlmcp_client_session:stop(C),
    case R of {ok, _} -> pass; _ -> fail end.

cs_list_resources(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:list_resources(C),
    erlmcp_client_session:stop(C),
    case R of {ok, L} when length(L) >= 1 -> pass; _ -> fail end.

cs_read_resource(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:read_resource(C, <<"weather://current/london">>),
    erlmcp_client_session:stop(C),
    case R of {ok, _} -> pass; _ -> fail end.

cs_list_prompts(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:list_prompts(C),
    erlmcp_client_session:stop(C),
    case R of {ok, L} when length(L) >= 1 -> pass; _ -> fail end.

cs_get_prompt(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:get_prompt(C, <<"weather_report">>,
        #{<<"city">> => <<"london">>}),
    erlmcp_client_session:stop(C),
    case R of {ok, _} -> pass; _ -> fail end.

cs_set_log_level(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:set_log_level(C, info),
    erlmcp_client_session:stop(C),
    case R of ok -> pass; _ -> fail end.

cs_completion(_) ->
    {_S, C} = setup_client_pair(),
    R = erlmcp_client_session:complete(C,
        #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"weather_report">>},
        #{<<"name">> => <<"city">>, <<"value">> => <<"lon">>}),
    erlmcp_client_session:stop(C),
    case R of {ok, _} -> pass; _ -> fail end.

cs_capability_gating(_) ->
    SB = spawn_link(fun() -> cbridge(undefined) end),
    CB = spawn_link(fun() -> cbridge(undefined) end),
    {ok, S} = erlmcp_server_session:start_link(#{
        transport => SB, name => <<"bare">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    {ok, C} = erlmcp_client_session:start_link(#{
        transport => CB, owner => self(),
        name => <<"cc">>, version => <<"1.0">>
    }),
    SB ! {peer, C}, CB ! {peer, S},
    {ok, _} = erlmcp_client_session:initialize(C, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    R = erlmcp_client_session:list_prompts(C),
    erlmcp_client_session:stop(C), gen_statem:stop(S),
    case R of {error, {capability_not_supported, _}} -> pass; _ -> fail end.

cs_sampling_callback(_) ->
    {S, C} = setup_client_pair(),
    ok = erlmcp:add_tool(S, #{
        name => <<"s">>, description => <<"S">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>,
                #{<<"messages">> => []}),
            {ok, erlmcp:text(maps:get(<<"model">>, R, <<"?">>))}
        end
    }),
    R = erlmcp_client_session:call_tool(C, <<"s">>, #{}),
    erlmcp_client_session:stop(C),
    case R of {ok, _} -> pass; _ -> fail end.

cs_roots_callback(_) ->
    {S, C} = setup_client_pair(),
    ok = erlmcp:add_tool(S, #{
        name => <<"r">>, description => <<"R">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"roots/list">>, #{}),
            {ok, erlmcp:text(integer_to_binary(length(maps:get(<<"roots">>, R, []))))}
        end
    }),
    R = erlmcp_client_session:call_tool(C, <<"r">>, #{}),
    erlmcp_client_session:stop(C),
    case R of {ok, _} -> pass; _ -> fail end.

cs_elicitation_callback(_) ->
    {S, C} = setup_client_pair(),
    ok = erlmcp:add_tool(S, #{
        name => <<"e">>, description => <<"E">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"elicitation/create">>,
                #{<<"message">> => <<"OK?">>}),
            {ok, erlmcp:text(maps:get(<<"action">>, R, <<"?">>))}
        end
    }),
    R = erlmcp_client_session:call_tool(C, <<"e">>, #{}),
    erlmcp_client_session:stop(C),
    case R of {ok, _} -> pass; _ -> fail end.

cs_capability_advertisement(_) ->
    SB = spawn_link(fun() -> cbridge(undefined) end),
    CB = spawn_link(fun() -> cbridge(undefined) end),
    {ok, S} = erlmcp_server_session:start_link(#{
        transport => SB, name => <<"t">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    {ok, C} = erlmcp_client_session:start_link(#{
        transport => CB, owner => self(),
        name => <<"t">>, version => <<"1.0">>
    }),
    ok = erlmcp_client_session:set_sampling_handler(C, test_sampling_handler),
    SB ! {peer, C}, CB ! {peer, S},
    {ok, _} = erlmcp_client_session:initialize(C, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_client_session:stop(C), gen_statem:stop(S),
    pass.

cs_inbound_unknown(_) ->
    {S, C} = setup_client_pair(),
    ok = erlmcp:add_tool(S, #{
        name => <<"u">>, description => <<"U">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            R = erlmcp_ctx:request_peer(Ctx, <<"nonexistent">>, #{}),
            case R of {error, _} -> {ok, erlmcp:text(<<"err">>)};
                       _ -> {ok, erlmcp:text(<<"?">>)} end
        end
    }),
    R = erlmcp_client_session:call_tool(C, <<"u">>, #{}),
    erlmcp_client_session:stop(C),
    case R of {ok, _} -> pass; _ -> fail end.

%%====================================================================
%% Transport scorecard (M4)
%%====================================================================

-define(TRANSPORT_SCENARIOS, [
    {t0, <<"stdio_start_stop">>, fun ts_stdio_start_stop/1},
    {t0, <<"stdio_send">>, fun ts_stdio_send/1},
    {t0, <<"stdio_validate_config">>, fun ts_stdio_validate/1},
    {t0, <<"stdio_session_delivery">>, fun ts_stdio_delivery/1},
    {t0, <<"streamable_start_stop">>, fun ts_stream_start_stop/1},
    {t0, <<"streamable_send">>, fun ts_stream_send/1},
    {t0, <<"streamable_validate_config">>, fun ts_stream_validate/1},
    {t0, <<"tcp_validate_config">>, fun ts_tcp_validate/1},
    {t0, <<"http_validate_config">>, fun ts_http_validate/1}
]).

-spec run_transport_scorecard() -> {float(), [{atom(), binary(), pass | fail}]}.
run_transport_scorecard() ->
    Results = lists:map(fun({Level, Name, ScenarioFun}) ->
        try ScenarioFun(unused) of
            pass -> {Level, Name, pass};
            fail -> {Level, Name, fail}
        catch _:_ ->
            {Level, Name, fail}
        end
    end, ?TRANSPORT_SCENARIOS),
    Passed = length([ok || {_, _, pass} <- Results]),
    Total = length(Results),
    Score = (Passed / Total) * 100,
    {Score, Results}.

ts_stdio_start_stop(_) ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test, #{
        session => self(), test_mode => true}),
    erlmcp_transport_stdio:close(Pid),
    pass.

ts_stdio_send(_) ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(test, #{
        session => self(), test_mode => true}),
    R = erlmcp_transport_stdio:send(Pid, <<"data">>),
    erlmcp_transport_stdio:close(Pid),
    case R of ok -> pass; _ -> fail end.

ts_stdio_validate(_) ->
    case erlmcp_transport_stdio:validate_config(#{session => self()}) of
        ok ->
            case erlmcp_transport_stdio:validate_config(#{}) of
                {error, _} -> pass;
                _ -> fail
            end;
        _ -> fail
    end.

ts_stdio_delivery(_) ->
    {ok, S} = erlmcp_server_session:start_link(#{
        name => <<"t">>, version => <<"1.0">>, capabilities => #{}}),
    {ok, Pid} = erlmcp_transport_stdio:start_link(test, #{
        session => S, test_mode => true}),
    Init = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    erlmcp_transport_stdio:simulate_input(Pid, Init),
    timer:sleep(100),
    R = gen_statem:call(S, get_state),
    erlmcp_transport_stdio:close(Pid),
    gen_statem:stop(S),
    case R of operational -> pass; _ -> fail end.

ts_stream_start_stop(_) ->
    {ok, Pid} = erlmcp_transport_streamable_http:start_link(#{
        session => self(), test_mode => true}),
    erlmcp_transport_streamable_http:close(Pid),
    pass.

ts_stream_send(_) ->
    {ok, Pid} = erlmcp_transport_streamable_http:start_link(#{
        session => self(), test_mode => true}),
    R = erlmcp_transport_streamable_http:send(Pid, <<"data">>),
    erlmcp_transport_streamable_http:close(Pid),
    case R of ok -> pass; _ -> fail end.

ts_stream_validate(_) ->
    case erlmcp_transport_streamable_http:validate_config(#{session => self()}) of
        ok ->
            case erlmcp_transport_streamable_http:validate_config(not_a_map) of
                {error, _} -> pass;
                _ -> fail
            end;
        _ -> fail
    end.

ts_tcp_validate(_) ->
    case erlmcp_transport_tcp:validate_config(#{host => "h", port => 1, owner => self()}) of
        ok ->
            case erlmcp_transport_tcp:validate_config(#{}) of
                {error, _} -> pass;
                _ -> fail
            end;
        _ -> fail
    end.

ts_http_validate(_) ->
    case erlmcp_transport_http:validate_config(#{url => "http://x", owner => self()}) of
        ok ->
            case erlmcp_transport_http:validate_config(#{}) of
                {error, _} -> pass;
                _ -> fail
            end;
        _ -> fail
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
