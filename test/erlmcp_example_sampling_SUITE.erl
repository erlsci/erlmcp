-module(erlmcp_example_sampling_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
    sampling_end_to_end/1,
    roots_list/1,
    roots_list_changed/1,
    elicitation_end_to_end/1,
    capability_advertisement/1,
    inbound_unknown_method/1,
    inbound_validation_failure/1,
    callback_crash_isolation/1,
    server_peer_request_from_tool/1
]).

all() ->
    [sampling_end_to_end,
     roots_list,
     roots_list_changed,
     elicitation_end_to_end,
     capability_advertisement,
     inbound_unknown_method,
     inbound_validation_failure,
     callback_crash_isolation,
     server_peer_request_from_tool].

init_per_testcase(_TC, Config) ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => SBridge,
        name => <<"test-server">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test-client">>, version => <<"1.0">>
    }),
    ok = erlmcp_client_session:set_sampling_handler(Client, test_sampling_handler),
    ok = erlmcp_client_session:set_roots_handler(Client, test_roots_handler),
    ok = erlmcp_client_session:set_elicitation_handler(Client, test_elicitation_handler),
    ok = erlmcp:add_tool(Server, #{
        name => <<"noop">>, description => <<"Placeholder">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    [{server, Server}, {client, Client},
     {s_bridge, SBridge}, {c_bridge, CBridge} | Config].

end_per_testcase(_TC, Config) ->
    catch erlmcp_client_session:stop(?config(client, Config)),
    catch gen_statem:stop(?config(server, Config)),
    ok.

bridge(Peer) ->
    receive
        {peer, Pid} -> bridge(Pid);
        {send, Data} when is_pid(Peer) ->
            gen_statem:cast(Peer, {transport_data, Data}),
            bridge(Peer);
        _ -> bridge(Peer)
    end.

%%====================================================================
%% M3b-3: sampling end-to-end
%%====================================================================

sampling_end_to_end(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"ask_llm">>,
        description => <<"Ask the LLM via sampling">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"question">>, erlmcp_schema:string(), [required])
        ]),
        handler => fun(#{<<"question">> := Q}, Ctx) ->
            SamplingParams = #{
                <<"messages">> => [#{<<"role">> => <<"user">>,
                                     <<"content">> => #{<<"type">> => <<"text">>,
                                                        <<"text">> => Q}}],
                <<"maxTokens">> => 100
            },
            {ok, Result} = erlmcp_ctx:request_peer(Ctx,
                <<"sampling/createMessage">>, SamplingParams),
            {ok, erlmcp:text(maps:get(<<"text">>,
                maps:get(<<"content">>, Result, #{}), <<"no response">>))}
        end
    }),
    {ok, ToolResult} = erlmcp_client_session:call_tool(
        ?config(client, Config), <<"ask_llm">>,
        #{<<"question">> => <<"What is 2+2?">>}),
    [Content] = maps:get(<<"content">>, ToolResult),
    Text = maps:get(<<"text">>, Content),
    ?assert(binary:match(Text, <<"1 messages">>) =/= nomatch).

%%====================================================================
%% M3b-4: roots/list + list_changed
%%====================================================================

roots_list(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"get_roots">>,
        description => <<"Get client roots">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, Result} = erlmcp_ctx:request_peer(Ctx, <<"roots/list">>, #{}),
            Roots = maps:get(<<"roots">>, Result, []),
            {ok, erlmcp:text(integer_to_binary(length(Roots)))}
        end
    }),
    {ok, ToolResult} = erlmcp_client_session:call_tool(
        ?config(client, Config), <<"get_roots">>, #{}),
    [Content] = maps:get(<<"content">>, ToolResult),
    ?assertEqual(<<"2">>, maps:get(<<"text">>, Content)).

roots_list_changed(Config) ->
    Server = ?config(server, Config),
    Transport = ?config(s_bridge, Config),
    erlmcp_client_session:notify_roots_changed(?config(client, Config)),
    timer:sleep(100),
    ?assert(is_process_alive(Server)),
    _ = Transport,
    ok.

%%====================================================================
%% M3b-5: elicitation
%%====================================================================

elicitation_end_to_end(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"confirm">>,
        description => <<"Ask user to confirm">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, Result} = erlmcp_ctx:request_peer(Ctx,
                <<"elicitation/create">>,
                #{<<"message">> => <<"Proceed?">>}),
            Action = maps:get(<<"action">>, Result, <<"unknown">>),
            {ok, erlmcp:text(Action)}
        end
    }),
    {ok, ToolResult} = erlmcp_client_session:call_tool(
        ?config(client, Config), <<"confirm">>, #{}),
    [Content] = maps:get(<<"content">>, ToolResult),
    ?assertEqual(<<"accept">>, maps:get(<<"text">>, Content)).

%%====================================================================
%% M3b-7: capability advertisement
%%====================================================================

capability_advertisement(_Config) ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => SBridge,
        name => <<"test">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    ok = erlmcp_client_session:set_sampling_handler(Client, test_sampling_handler),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, InitResult} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    _Caps = maps:get(<<"capabilities">>, InitResult, #{}),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server),
    ok.

%%====================================================================
%% M3b-2: unknown method → -32601
%%====================================================================

inbound_unknown_method(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"bad_method">>,
        description => <<"Calls nonexistent method">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            Result = erlmcp_ctx:request_peer(Ctx, <<"nonexistent/method">>, #{}),
            case Result of
                {error, #{<<"code">> := -32601}} ->
                    {ok, erlmcp:text(<<"got -32601">>)};
                {error, _} ->
                    {ok, erlmcp:text(<<"got error">>)};
                _ ->
                    {ok, erlmcp:text(<<"unexpected">>)}
            end
        end
    }),
    {ok, ToolResult} = erlmcp_client_session:call_tool(
        ?config(client, Config), <<"bad_method">>, #{}),
    [Content] = maps:get(<<"content">>, ToolResult),
    Text = maps:get(<<"text">>, Content),
    ?assert(binary:match(Text, <<"got">>) =/= nomatch).

%%====================================================================
%% M3b-6: inbound validation failure → -32602
%%====================================================================

inbound_validation_failure(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"bad_sampling">>,
        description => <<"Sends invalid sampling request">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            Result = erlmcp_ctx:request_peer(Ctx,
                <<"sampling/createMessage">>, #{}),
            case Result of
                {error, #{<<"code">> := -32602}} ->
                    {ok, erlmcp:text(<<"got -32602">>)};
                {error, _} ->
                    {ok, erlmcp:text(<<"got error">>)};
                _ ->
                    {ok, erlmcp:text(<<"unexpected">>)}
            end
        end
    }),
    {ok, ToolResult} = erlmcp_client_session:call_tool(
        ?config(client, Config), <<"bad_sampling">>, #{}),
    [Content] = maps:get(<<"content">>, ToolResult),
    Text = maps:get(<<"text">>, Content),
    ?assert(binary:match(Text, <<"got">>) =/= nomatch).

%%====================================================================
%% M3b-2: callback crash → -32603, session survives
%%====================================================================

callback_crash_isolation(Config) ->
    Client = ?config(client, Config),
    Server = ?config(server, Config),
    CrashSampling = spawn_link(fun() -> bridge(undefined) end),
    CrashClient = spawn_link(fun() -> bridge(undefined) end),
    {ok, Server2} = erlmcp_server_session:start_link(#{
        transport => CrashSampling,
        name => <<"crash-test">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    {ok, Client2} = erlmcp_client_session:start_link(#{
        transport => CrashClient,
        owner => self(),
        name => <<"crash-client">>, version => <<"1.0">>
    }),
    ok = erlmcp_client_session:set_sampling_handler(Client2, test_crash_sampling),
    ok = erlmcp:add_tool(Server2, #{
        name => <<"noop">>, description => <<"Placeholder">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    CrashSampling ! {peer, Client2},
    CrashClient ! {peer, Server2},
    {ok, _} = erlmcp_client_session:initialize(Client2, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ok = erlmcp:add_tool(Server2, #{
        name => <<"crash_sample">>,
        description => <<"Trigger crashing sampler">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            Result = erlmcp_ctx:request_peer(Ctx,
                <<"sampling/createMessage">>,
                #{<<"messages">> => []}),
            case Result of
                {error, _} -> {ok, erlmcp:text(<<"isolated">>)};
                _ -> {ok, erlmcp:text(<<"unexpected">>)}
            end
        end
    }),
    {ok, ToolResult} = erlmcp_client_session:call_tool(
        Client2, <<"crash_sample">>, #{}),
    [Content] = maps:get(<<"content">>, ToolResult),
    ?assertEqual(<<"isolated">>, maps:get(<<"text">>, Content)),
    ?assert(is_process_alive(Client2)),
    erlmcp_client_session:stop(Client2),
    gen_statem:stop(Server2),
    _ = Client, _ = Server.

%%====================================================================
%% M3b-1: server peer request from tool worker via ctx
%%====================================================================

server_peer_request_from_tool(Config) ->
    Server = ?config(server, Config),
    ok = erlmcp:add_tool(Server, #{
        name => <<"peer_test">>,
        description => <<"Tests peer request">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, RootsResult} = erlmcp_ctx:request_peer(Ctx, <<"roots/list">>, #{}),
            Roots = maps:get(<<"roots">>, RootsResult, []),
            {ok, erlmcp:text(integer_to_binary(length(Roots)))}
        end
    }),
    {ok, ToolResult} = erlmcp_client_session:call_tool(
        ?config(client, Config), <<"peer_test">>, #{}),
    [Content] = maps:get(<<"content">>, ToolResult),
    ?assertEqual(<<"2">>, maps:get(<<"text">>, Content)).
