-module(erlmcp_cross_node_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([sampling_cross_node/1, elicitation_cross_node/1]).

all() ->
    [sampling_cross_node, elicitation_cross_node].

init_per_suite(Config) ->
    case node() of
        'nonode@nohost' ->
            case net_kernel:start([erlmcp_test_node, shortnames]) of
                {ok, _} -> [{started_dist, true} | Config];
                {error, _} -> {skip, "Distribution not available"}
            end;
        _ ->
            Config
    end.

end_per_suite(Config) ->
    case proplists:get_value(started_dist, Config, false) of
        true -> net_kernel:stop();
        false -> ok
    end,
    ok.

init_per_testcase(_TC, Config) ->
    case start_peer_node() of
        {ok, PeerNode} ->
            try setup_cross_node(PeerNode) of
                {Srv, Server, Client} ->
                    [{peer_node, PeerNode}, {srv, Srv},
                     {server, Server}, {client, Client} | Config]
            catch _:Reason ->
                stop_peer_node(PeerNode),
                {skip, {cross_node_setup_failed, Reason}}
            end;
        {error, Reason} ->
            {skip, {cannot_start_peer, Reason}}
    end.

end_per_testcase(_TC, Config) ->
    catch erlmcp_client_session:stop(?config(client, Config)),
    catch gen_statem:stop(?config(server, Config)),
    catch gen_server:stop(?config(srv, Config)),
    case proplists:get_value(peer_node, Config, undefined) of
        undefined -> ok;
        Node -> stop_peer_node(Node)
    end,
    ok.

%%====================================================================
%% Cross-node tests
%%====================================================================

sampling_cross_node(Config) ->
    Srv = ?config(srv, Config),
    Client = ?config(client, Config),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"ask">>, description => <<"Ask">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>,
                #{<<"messages">> => [#{<<"role">> => <<"user">>,
                    <<"content">> => #{<<"type">> => <<"text">>,
                                       <<"text">> => <<"hi">>}}]}),
            {ok, erlmcp:text(maps:get(<<"model">>, R, <<"?">>))}
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"ask">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"test-model">>, maps:get(<<"text">>, C)).

elicitation_cross_node(Config) ->
    Srv = ?config(srv, Config),
    Client = ?config(client, Config),
    ok = erlmcp:add_tool(Srv, #{
        name => <<"confirm">>, description => <<"Confirm">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, Ctx) ->
            {ok, R} = erlmcp_ctx:request_peer(Ctx, <<"elicitation/create">>,
                #{<<"message">> => <<"OK?">>}),
            {ok, erlmcp:text(maps:get(<<"action">>, R, <<"?">>))}
        end
    }),
    {ok, Result} = erlmcp_client_session:call_tool(Client, <<"confirm">>, #{}),
    [C] = maps:get(<<"content">>, Result),
    ?assertEqual(<<"accept">>, maps:get(<<"text">>, C)).

%%====================================================================
%% Cross-node setup — server on this node, client on peer
%%====================================================================

setup_cross_node({_Pid, PeerNode}) ->
    SBridge = spawn_link(fun() -> dist_bridge(undefined) end),
    CBridge = rpc:call(PeerNode, erlang, spawn_link,
                       [fun() -> dist_bridge(undefined) end]),
    is_pid(CBridge) orelse error({peer_spawn_failed, CBridge}),
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"cross-server">>, version => <<"1.0">>,
        tools => [#{name => <<"noop">>, description => <<"Noop">>,
                    input_schema => erlmcp_schema:object([]),
                    handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end}]
    }),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"cross-server">>, version => <<"1.0">>
    }),
    {ok, Client} = rpc:call(PeerNode, erlmcp_client_session, start_link, [#{
        transport => CBridge,
        owner => self(),
        name => <<"cross-client">>, version => <<"1.0">>
    }]),
    ok = rpc:call(PeerNode, erlmcp_client_session, set_sampling_handler,
                  [Client, test_sampling_handler]),
    ok = rpc:call(PeerNode, erlmcp_client_session, set_elicitation_handler,
                  [Client, test_elicitation_handler]),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    {Srv, Server, Client}.

dist_bridge(Peer) ->
    receive
        {peer, Pid} -> dist_bridge(Pid);
        {send, Data} when is_pid(Peer) ->
            gen_statem:cast(Peer, {transport_data, Data}),
            dist_bridge(Peer);
        _ -> dist_bridge(Peer)
    end.

%%====================================================================
%% Peer node management
%%====================================================================

start_peer_node() ->
    try
        Name = list_to_atom("erlmcp_peer_" ++ integer_to_list(
            erlang:unique_integer([positive]))),
        case peer:start_link(#{name => Name, connection => standard_io}) of
            {ok, Pid, Node} ->
                ok = add_code_paths(Node),
                {ok, {Pid, Node}};
            {error, _} = Err ->
                Err
        end
    catch _:_ ->
        {error, peer_not_available}
    end.

stop_peer_node({Pid, _Node}) ->
    peer:stop(Pid).

add_code_paths(Node) ->
    Paths = code:get_path(),
    rpc:call(Node, code, add_pathsa, [Paths]),
    ok.
