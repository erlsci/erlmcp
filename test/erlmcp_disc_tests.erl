-module(erlmcp_disc_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Helpers — set up a session with the calculator + directory tools
%%====================================================================

setup() ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"test-server">>, version => <<"1.0">>,
        handler => example_calculator_handler
    }),
    ok = erlmcp:add_tool(Server, erlmcp:make_directory_tool()),
    Server.

setup_session() ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>,
        handler => example_calculator_handler
    }),
    ok = erlmcp:add_tool(Srv, erlmcp:make_directory_tool()),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    {Srv, Session}.

teardown(Server) ->
    gen_server:stop(Server).

teardown_session({Srv, Session}) ->
    catch gen_statem:stop(Session),
    catch gen_server:stop(Srv).

%%====================================================================
%% DISC-1: Every tool has non-empty category and when_to_use
%%====================================================================

test_all_tools_have_metadata_test() ->
    Server = setup(),
    Tools = erlmcp:conformance_tools(Server),
    lists:foreach(fun(T) ->
        Name = maps:get(name, T),
        Cat = maps:get(category, T, <<>>),
        WTU = maps:get(when_to_use, T, <<>>),
        ?assertNotEqual(<<>>, Cat,
            lists:flatten(io_lib:format("~s missing category", [Name]))),
        ?assertNotEqual(<<>>, WTU,
            lists:flatten(io_lib:format("~s missing when_to_use", [Name])))
    end, Tools),
    teardown(Server).

%%====================================================================
%% DISC-2: next graph has no dangling edges
%%====================================================================

test_next_graph_no_dangling_edges_test() ->
    Server = setup(),
    Tools = erlmcp:conformance_tools(Server),
    RegisteredNames = [maps:get(name, T) || T <- Tools],
    AllNextTargets = lists:flatten(
        [maps:get(next, T, []) || T <- Tools]),
    Dangling = [N || N <- AllNextTargets,
                     not lists:member(N, RegisteredNames)],
    ?assertEqual([], Dangling),
    teardown(Server).

%%====================================================================
%% DISC-3: No orphan tools — all reachable from entry points
%%====================================================================

test_all_tools_reachable_from_entrypoints_test() ->
    Server = setup(),
    Tools = erlmcp:conformance_tools(Server),
    ToolNames = [maps:get(name, T) || T <- Tools],
    Explicit = [maps:get(name, T) || T <- Tools,
                    maps:get(entry_point, T, false) =:= true],
    EntryPointNames = case Explicit of
        [] ->
            AllNextTargets = lists:usort(lists:flatten(
                [maps:get(next, T, []) || T <- Tools])),
            [N || N <- ToolNames, not lists:member(N, AllNextTargets)];
        _ -> Explicit
    end,
    AllNameSet = sets:from_list(ToolNames),
    NextMap = maps:from_list([{maps:get(name, T), maps:get(next, T, [])}
                              || T <- Tools]),
    Reachable = bfs(EntryPointNames, NextMap, sets:new()),
    Unreachable = sets:subtract(AllNameSet, Reachable),
    ?assertEqual([], sets:to_list(Unreachable)),
    teardown(Server).

bfs([], _NextMap, Visited) ->
    Visited;
bfs([Node | Queue], NextMap, Visited) ->
    case sets:is_element(Node, Visited) of
        true ->
            bfs(Queue, NextMap, Visited);
        false ->
            NewVisited = sets:add_element(Node, Visited),
            Neighbors = maps:get(Node, NextMap, []),
            bfs(Queue ++ Neighbors, NextMap, NewVisited)
    end.

%%====================================================================
%% DISC-4: All surfaces share one source — registration map
%%====================================================================

test_surfaces_share_source_test() ->
    {_Srv, Server} = setup_session(),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    InitResp = decode(wait_send()),
    Instructions = maps:get(<<"instructions">>,
                            maps:get(<<"result">>, InitResp)),
    ?assert(binary:match(Instructions, <<"arithmetic">>) =/= nomatch),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq),
    ListResp = decode(wait_send()),
    ToolsList = maps:get(<<"tools">>,
                         maps:get(<<"result">>, ListResp)),
    AddTool = hd([T || T <- ToolsList,
                        maps:get(<<"name">>, T) =:= <<"add">>]),
    Meta = maps:get(<<"_meta">>, AddTool),
    ?assertEqual(<<"arithmetic">>,
                 maps:get(<<"io.erlmcp/category">>, Meta)),
    ?assertEqual(<<"When you need to add two numbers">>,
                 maps:get(<<"io.erlmcp/when_to_use">>, Meta)),
    gen_statem:stop(Server).

%%====================================================================
%% DISC-5: _meta keys use io.erlmcp/ prefix and conform to grammar
%%====================================================================

test_meta_key_namespace_test() ->
    {_DSrv, Server} = setup_session(),
    init_session(Server),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq),
    ListResp = decode(wait_send()),
    ToolsList = maps:get(<<"tools">>,
                         maps:get(<<"result">>, ListResp)),
    Pattern = "^io\\.erlmcp/[A-Za-z0-9][A-Za-z0-9._-]*$",
    {ok, Re} = re:compile(Pattern),
    lists:foreach(fun(Tool) ->
        case maps:get(<<"_meta">>, Tool, undefined) of
            undefined -> ok;
            Meta ->
                maps:foreach(fun(Key, _Val) ->
                    case re:run(Key, Re) of
                        {match, _} -> ok;
                        nomatch ->
                            ?assert(false,
                                lists:flatten(io_lib:format(
                                    "Bad _meta key: ~s", [Key])))
                    end
                end, Meta)
        end
    end, ToolsList),
    gen_statem:stop(Server).

%%====================================================================
%% DISC-6: Directory tool covers all tools, excluded from conformance
%%====================================================================

test_directory_covers_all_tools_test() ->
    {DSrv, Server} = setup_session(),
    ok = erlmcp:add_tool(DSrv, erlmcp:make_directory_tool()),
    init_session(Server),
    CallReq = erlmcp_json_rpc:encode_request(2, <<"tools/call">>, #{
        <<"name">> => <<"directory">>,
        <<"arguments">> => #{}
    }),
    erlmcp_server_session:send_message(Server, CallReq),
    Resp = decode(wait_send()),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"content">>, Result),
    DirJson = maps:get(<<"text">>, Content),
    {ok, DirMap} = erlmcp_codec:decode(DirJson),
    ToolsByCat = maps:get(<<"tools">>, DirMap),
    DirToolCount = lists:sum([length(V) || V <- maps:values(ToolsByCat)]),
    ConformanceTools = erlmcp:conformance_tools(DSrv),
    ?assertEqual(length(ConformanceTools), DirToolCount),
    gen_statem:stop(Server),
    gen_server:stop(DSrv).

test_directory_excluded_from_conformance_test() ->
    Server = setup(),
    ConformanceTools = erlmcp:conformance_tools(Server),
    Names = [maps:get(name, T) || T <- ConformanceTools],
    ?assertNot(lists:member(<<"directory">>, Names)),
    teardown(Server).

%%====================================================================
%% DISC-7: Behavioral hints in annotations, not in _meta
%%====================================================================

test_no_behavioral_keys_in_meta_test() ->
    {_DSrv, Server} = setup_session(),
    init_session(Server),
    ListReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq),
    ListResp = decode(wait_send()),
    ToolsList = maps:get(<<"tools">>,
                         maps:get(<<"result">>, ListResp)),
    Forbidden = [<<"readOnlyHint">>, <<"destructiveHint">>,
                 <<"idempotentHint">>, <<"openWorldHint">>],
    lists:foreach(fun(Tool) ->
        case maps:get(<<"_meta">>, Tool, undefined) of
            undefined -> ok;
            Meta ->
                lists:foreach(fun(Key) ->
                    ?assertNot(maps:is_key(Key, Meta))
                end, Forbidden)
        end
    end, ToolsList),
    gen_statem:stop(Server).

%%====================================================================
%% DISC-8: instructions doesn't enumerate tools; byte-identical
%%        after runtime add/remove
%%====================================================================

test_instructions_no_tool_enumeration_test() ->
    {DSrv, Server} = setup_session(),
    ok = erlmcp:add_tool(DSrv, erlmcp:make_directory_tool()),
    init_session(Server),
    Instructions = erlmcp_server_session:get_instructions(Server),
    NonEntryToolNames = [<<"subtract">>, <<"multiply">>, <<"divide">>],
    lists:foreach(fun(Name) ->
        ?assertEqual(nomatch, binary:match(Instructions, Name),
            lists:flatten(io_lib:format(
                "instructions should not contain ~s", [Name])))
    end, NonEntryToolNames),
    ok = erlmcp:add_tool(DSrv, #{
        name => <<"sqrt">>,
        description => <<"Square root">>,
        input_schema => erlmcp_schema:object([]),
        category => <<"arithmetic">>,
        when_to_use => <<"When you need a square root">>,
        handler => fun(_, _) -> {ok, erlmcp:text(<<"1">>)} end
    }),
    _ = wait_send(),
    InstructionsAfterAdd = erlmcp_server_session:get_instructions(Server),
    ?assertEqual(Instructions, InstructionsAfterAdd),
    ok = erlmcp:remove_tool(DSrv, <<"sqrt">>),
    _ = wait_send(),
    InstructionsAfterRemove = erlmcp_server_session:get_instructions(Server),
    ?assertEqual(Instructions, InstructionsAfterRemove),
    gen_statem:stop(Server),
    gen_server:stop(DSrv).

%%====================================================================
%% DISC-9: Runtime changes reflected in directory and _meta
%%====================================================================

test_runtime_change_reflected_test() ->
    {DSrv, Server} = setup_session(),
    ok = erlmcp:add_tool(DSrv, erlmcp:make_directory_tool()),
    init_session(Server),
    ok = erlmcp:add_tool(DSrv, #{
        name => <<"modulo">>,
        description => <<"Modulo operation">>,
        input_schema => erlmcp_schema:object([]),
        category => <<"arithmetic">>,
        when_to_use => <<"When you need the remainder">>,
        handler => fun(_, _) -> {ok, erlmcp:text(<<"0">>)} end
    }),
    _ = wait_send(),
    ListReq1 = erlmcp_json_rpc:encode_request(3, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq1),
    ListResp1 = decode(wait_send()),
    Names1 = [maps:get(<<"name">>, T)
              || T <- maps:get(<<"tools">>,
                               maps:get(<<"result">>, ListResp1))],
    ?assert(lists:member(<<"modulo">>, Names1)),
    ok = erlmcp:remove_tool(DSrv, <<"modulo">>),
    _ = wait_send(),
    ListReq2 = erlmcp_json_rpc:encode_request(4, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Server, ListReq2),
    ListResp2 = decode(wait_send()),
    Names2 = [maps:get(<<"name">>, T)
              || T <- maps:get(<<"tools">>,
                               maps:get(<<"result">>, ListResp2))],
    ?assertNot(lists:member(<<"modulo">>, Names2)),
    gen_statem:stop(Server).

%%====================================================================
%% Internal helpers
%%====================================================================

init_session(Server) ->
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
