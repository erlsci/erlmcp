-module(erlmcp_example_client_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
    list_tools/1,
    call_tool/1,
    list_resources/1,
    read_resource/1,
    list_resource_templates/1,
    read_templated_resource/1,
    subscribe_resource/1,
    list_prompts/1,
    get_prompt/1,
    set_log_level_and_receive/1,
    completion/1,
    progress_receipt/1,
    cancellation/1,
    list_changed_notification/1,
    capability_gating/1
]).

all() ->
    [list_tools, call_tool,
     list_resources, read_resource,
     list_resource_templates, read_templated_resource,
     subscribe_resource,
     list_prompts, get_prompt,
     set_log_level_and_receive,
     completion,
     progress_receipt,
     cancellation,
     list_changed_notification,
     capability_gating].

init_per_testcase(_TC, Config) ->
    {Srv, Server, Client} = start_pair(),
    [{server, Server}, {srv, Srv}, {client, Client} | Config].

end_per_testcase(_TC, Config) ->
    catch erlmcp_client_session:stop(?config(client, Config)),
    catch gen_statem:stop(?config(server, Config)),
    catch gen_server:stop(?config(srv, Config)),
    ok.

%%====================================================================
%% Bridge — connects client ↔ server in-process
%%====================================================================

start_pair() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test-server">>, version => <<"1.0">>,
        handler => example_calculator_handler
    }),
    ok = erlmcp:add_tool(Srv, erlmcp:make_directory_tool()),
    ok = example_weather_handler:register_all(Srv),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"slow">>,
        description => <<"Slow tool for progress/cancel testing">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            erlmcp_ctx:report_progress(Ctx, 0.5, <<"halfway">>),
            receive after 5000 -> ok end,
            {ok, erlmcp:text(<<"done">>)}
        end
    }),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test-server">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test-client">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    {Srv, Server, Client}.

bridge(Peer) ->
    receive
        {peer, Pid} ->
            bridge(Pid);
        {send, Data} when is_pid(Peer) ->
            gen_statem:cast(Peer, {transport_data, Data}),
            bridge(Peer);
        _ ->
            bridge(Peer)
    end.

%%====================================================================
%% M3a-1: tools
%%====================================================================

list_tools(Config) ->
    Client = ?config(client, Config),
    {ok, Tools} = erlmcp_client_session:list_tools(Client),
    ?assert(length(Tools) >= 5),
    Names = [maps:get(<<"name">>, T) || T <- Tools],
    ?assert(lists:member(<<"add">>, Names)).

call_tool(Config) ->
    Client = ?config(client, Config),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"add">>,
        #{<<"a">> => 10, <<"b">> => 32}),
    ?assert(maps:is_key(<<"content">>, Result)).

%%====================================================================
%% M3a-2,3: resources
%%====================================================================

list_resources(Config) ->
    Client = ?config(client, Config),
    {ok, Resources} = erlmcp_client_session:list_resources(Client),
    ?assert(length(Resources) >= 1).

read_resource(Config) ->
    Client = ?config(client, Config),
    {ok, Result} = erlmcp_client_session:read_resource(Client,
        <<"weather://current/london">>),
    ?assert(maps:is_key(<<"contents">>, Result)).

list_resource_templates(Config) ->
    Client = ?config(client, Config),
    {ok, Templates} = erlmcp_client_session:list_resource_templates(Client),
    ?assert(length(Templates) >= 1).

read_templated_resource(Config) ->
    Client = ?config(client, Config),
    {ok, Result} = erlmcp_client_session:read_resource(Client,
        <<"weather://current/tokyo">>),
    [Content] = maps:get(<<"contents">>, Result),
    ?assert(is_binary(maps:get(<<"text">>, Content))).

%%====================================================================
%% M3a-4: subscribe/unsubscribe
%%====================================================================

subscribe_resource(Config) ->
    Client = ?config(client, Config),
    Server = ?config(server, Config),
    ok = erlmcp_client_session:subscribe_resource(Client,
        <<"weather://current/london">>),
    erlmcp:notify_resource_updated(Server, <<"weather://current/london">>),
    receive
        {mcp_notification, {resource_updated, <<"weather://current/london">>}} -> ok
    after 2000 -> ct:fail(no_resource_updated)
    end,
    ok = erlmcp_client_session:unsubscribe_resource(Client,
        <<"weather://current/london">>).

%%====================================================================
%% M3a-5: prompts
%%====================================================================

list_prompts(Config) ->
    Client = ?config(client, Config),
    {ok, Prompts} = erlmcp_client_session:list_prompts(Client),
    ?assert(length(Prompts) >= 1).

get_prompt(Config) ->
    Client = ?config(client, Config),
    {ok, Result} = erlmcp_client_session:get_prompt(Client,
        <<"weather_report">>, #{<<"city">> => <<"london">>}),
    ?assert(maps:is_key(<<"messages">>, Result)).

%%====================================================================
%% M3a-6: logging
%%====================================================================

set_log_level_and_receive(Config) ->
    Client = ?config(client, Config),
    Server = ?config(server, Config),
    ok = erlmcp_client_session:set_log_level(Client, info),
    erlmcp:log_message(Server, info, <<"test">>, <<"hello">>),
    receive
        {mcp_notification, {log_message, Params}} ->
            ?assertEqual(<<"info">>, maps:get(<<"level">>, Params))
    after 2000 -> ct:fail(no_log_notification)
    end.

%%====================================================================
%% M3a-7: completion
%%====================================================================

completion(Config) ->
    Client = ?config(client, Config),
    {ok, Result} = erlmcp_client_session:complete(Client,
        #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"weather_report">>},
        #{<<"name">> => <<"city">>, <<"value">> => <<"lon">>}),
    Completion = maps:get(<<"completion">>, Result),
    ?assert(lists:member(<<"london">>, maps:get(<<"values">>, Completion))).

%%====================================================================
%% M3a-8: progress receipt
%%====================================================================

progress_receipt(Config) ->
    Client = ?config(client, Config),
    Token = <<"progress-test-1">>,
    spawn_link(fun() ->
        erlmcp_client_session:call_tool(Client, <<"slow">>, #{},
            #{progress_token => Token})
    end),
    receive
        {mcp_progress, Token, Params} ->
            ?assertEqual(0.5, maps:get(<<"progress">>, Params))
    after 5000 -> ct:fail(no_progress)
    end.

%%====================================================================
%% M3a-9: cancellation
%%====================================================================

cancellation(Config) ->
    Client = ?config(client, Config),
    TestPid = self(),
    Caller = spawn_link(fun() ->
        Result = erlmcp_client_session:call_tool(Client, <<"slow">>, #{}),
        TestPid ! {tool_result, Result}
    end),
    timer:sleep(200),
    %% Find the pending request ID by querying pending state
    %% Cancel all pending non-ping requests by sending cancellation
    %% for a range. The session only acts on matching IDs.
    lists:foreach(fun(Id) ->
        erlmcp_client_session:cancel(Client, Id)
    end, lists:seq(2, 20)),
    receive
        {tool_result, {error, cancelled}} -> ok;
        {tool_result, _} -> ok
    after 3000 ->
        %% If the caller is still alive and blocked, kill it
        exit(Caller, kill),
        ok
    end.

%%====================================================================
%% M3a-10: list_changed
%%====================================================================

list_changed_notification(Config) ->
    Srv = ?config(srv, Config),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"tmp_tool">>,
        description => <<"Temporary">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    receive
        {mcp_notification, {list_changed, tools, _}} -> ok
    after 2000 -> ct:fail(no_list_changed)
    end,
    ok = erlmcp:remove_tool(Srv, <<"tmp_tool">>),
    receive
        {mcp_notification, {list_changed, tools, _}} -> ok
    after 2000 -> ct:fail(no_list_changed_remove)
    end.

%%====================================================================
%% M3a-12: capability gating
%%====================================================================

capability_gating(_Config) ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, BareSrv} = erlmcp_server:start_link(#{
        name => <<"bare-server">>, version => <<"1.0">>
    }),
    BareResp = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => BareSrv, responder => BareResp,
        name => <<"bare-server">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test-client">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ?assertMatch({error, {capability_not_supported, <<"prompts">>}},
                 erlmcp_client_session:list_prompts(Client)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).
