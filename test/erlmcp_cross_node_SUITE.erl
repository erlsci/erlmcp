-module(erlmcp_cross_node_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([sampling_cross_node/1, elicitation_cross_node/1]).

all() ->
    [sampling_cross_node, elicitation_cross_node].

init_per_suite(Config) ->
    case net_kernel:longnames() of
        true -> Config;
        false -> Config;
        ignored ->
            {ok, _} = net_kernel:start([erlmcp_test_node, shortnames]),
            [{started_dist, true} | Config]
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
            [{peer_node, PeerNode} | Config];
        {error, Reason} ->
            {skip, {cannot_start_peer, Reason}}
    end.

end_per_testcase(_TC, Config) ->
    case proplists:get_value(peer_node, Config, undefined) of
        undefined -> ok;
        Node -> stop_peer_node(Node)
    end,
    ok.

%%====================================================================
%% Cross-node tests
%%====================================================================

sampling_cross_node(Config) ->
    PeerNode = ?config(peer_node, Config),
    {Server, Client} = setup_cross_node(PeerNode),
    ok = erlmcp:add_tool(Server, #{
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
    ?assertEqual(<<"test-model">>, maps:get(<<"text">>, C)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).

elicitation_cross_node(Config) ->
    PeerNode = ?config(peer_node, Config),
    {Server, Client} = setup_cross_node(PeerNode),
    ok = erlmcp:add_tool(Server, #{
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
    ?assertEqual(<<"accept">>, maps:get(<<"text">>, C)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).

%%====================================================================
%% Cross-node setup — server on this node, client on peer
%%====================================================================

setup_cross_node(PeerNode) ->
    SBridge = spawn_link(fun() -> dist_bridge(undefined) end),
    CBridge = rpc:call(PeerNode, erlang, spawn_link,
                       [fun() -> dist_bridge(undefined) end]),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => SBridge,
        name => <<"cross-server">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp:add_tool(Server, #{
        name => <<"noop">>, description => <<"Noop">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
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
    {Server, Client}.

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
