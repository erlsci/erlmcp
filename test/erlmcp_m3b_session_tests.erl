-module(erlmcp_m3b_session_tests).

-include_lib("eunit/include/eunit.hrl").

bridge(Peer) ->
    receive
        {peer, Pid} -> bridge(Pid);
        {send, Data} when is_pid(Peer) ->
            gen_statem:cast(Peer, {transport_data, Data}),
            bridge(Peer);
        _ -> bridge(Peer)
    end.

setup_pair() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test-server">>, version => <<"1.0">>,
        tools => [#{name => <<"noop">>, description => <<"Noop">>,
                    input_schema => erlmcp_schema:object([]),
                    handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end}]
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
    ok = erlmcp_client_session:set_sampling_handler(Client, test_sampling_handler),
    ok = erlmcp_client_session:set_roots_handler(Client, test_roots_handler),
    ok = erlmcp_client_session:set_elicitation_handler(Client, test_elicitation_handler),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    {Srv, Server, Client}.

%%====================================================================
%% Sampling end-to-end
%%====================================================================

sampling_test() ->
    {Srv, Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"sample">>, description => <<"Sample">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>,
                #{<<"messages">> => [#{<<"role">> => <<"user">>,
                    <<"content">> => #{<<"type">> => <<"text">>, <<"text">> => <<"hi">>}}]}),
            {ok, erlmcp:text(maps:get(<<"model">>, R, <<"?">>))}
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"sample">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"test-model">>, maps:get(<<"text">>, C)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Roots
%%====================================================================

roots_test() ->
    {Srv, Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"roots">>, description => <<"Roots">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"roots/list">>, #{}),
            N = length(maps:get(<<"roots">>, R, [])),
            {ok, erlmcp:text(integer_to_binary(N))}
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"roots">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"2">>, maps:get(<<"text">>, C)),
    erlmcp_client_session:stop(Client).

roots_changed_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    erlmcp_client_session:notify_roots_changed(Client),
    timer:sleep(100),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Elicitation
%%====================================================================

elicitation_test() ->
    {Srv, Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"elicit">>, description => <<"Elicit">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"elicitation/create">>,
                #{<<"message">> => <<"OK?">>}),
            {ok, erlmcp:text(maps:get(<<"action">>, R, <<"?">>))}
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"elicit">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"accept">>, maps:get(<<"text">>, C)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Unknown method → -32601
%%====================================================================

unknown_method_test() ->
    {Srv, Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"unknown">>, description => <<"Unknown">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            Res = erlmcp_ctx:request_peer(Ctx, <<"nonexistent">>, #{}),
            case Res of
                {error, _} -> {ok, erlmcp:text(<<"error">>)};
                _ -> {ok, erlmcp:text(<<"unexpected">>)}
            end
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"unknown">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"error">>, maps:get(<<"text">>, C)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Validation failure → -32602
%%====================================================================

validation_failure_test() ->
    {Srv, Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"invalid">>, description => <<"Invalid">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            Res = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>, #{}),
            case Res of
                {error, _} -> {ok, erlmcp:text(<<"error">>)};
                _ -> {ok, erlmcp:text(<<"unexpected">>)}
            end
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"invalid">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"error">>, maps:get(<<"text">>, C)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Callback crash isolation
%%====================================================================

callback_crash_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, CrashSrv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>,
        tools => [#{name => <<"noop">>, description => <<"Noop">>,
                    input_schema => erlmcp_schema:object([]),
                    handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end}]
    }),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => CrashSrv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge, owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    ok = erlmcp_client_session:set_sampling_handler(Client, test_crash_sampling),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ok = erlmcp:add_tool(CrashSrv, #{
        name => <<"crash">>, description => <<"Crash">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            Res = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>,
                #{<<"messages">> => []}),
            case Res of
                {error, _} -> {ok, erlmcp:text(<<"isolated">>)};
                _ -> {ok, erlmcp:text(<<"unexpected">>)}
            end
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"crash">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"isolated">>, maps:get(<<"text">>, C)),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).

%%====================================================================
%% Capability advertisement
%%====================================================================

capability_advertisement_test() ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, _AdvSrv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>
    }),
    AdvResp = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => _AdvSrv, responder => AdvResp,
        name => <<"test">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge, owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    ok = erlmcp_client_session:set_sampling_handler(Client, test_sampling_handler),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).

%%====================================================================
%% Handler registration in operational state
%%====================================================================

set_handler_operational_test() ->
    {_Srv, _Server, Client} = setup_pair(),
    ok = erlmcp_client_session:set_sampling_handler(Client, test_sampling_handler),
    ok = erlmcp_client_session:set_roots_handler(Client, test_roots_handler),
    ok = erlmcp_client_session:set_elicitation_handler(Client, test_elicitation_handler),
    ?assert(is_process_alive(Client)),
    erlmcp_client_session:stop(Client).

%%====================================================================
%% Inbound request in client — dispatch + response wire
%%====================================================================

inbound_request_wire_test() ->
    {Srv, Server, Client} = setup_pair(),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"wire">>, description => <<"Wire test">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"roots/list">>, #{}),
            Roots = maps:get(<<"roots">>, R, []),
            Names = [maps:get(<<"name">>, Root, <<>>) || Root <- Roots],
            {ok, erlmcp:text(iolist_to_binary(lists:join(<<",">>, Names)))}
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"wire">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    Text = maps:get(<<"text">>, C),
    ?assert(binary:match(Text, <<"Project Root">>) =/= nomatch),
    erlmcp_client_session:stop(Client).
