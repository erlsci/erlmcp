-module(erlmcp_http_sup).

-behaviour(supervisor).

-export([start_link/1, get_port/1]).
-export([init/1]).

-spec start_link(map()) -> {ok, pid()} | {error, term()} | ignore.
start_link(Config) when is_map(Config) ->
    case supervisor:start_link(?MODULE, []) of
        {ok, Sup} ->
            case wire_children(Sup, Config) of
                ok -> {ok, Sup};
                {error, _} = Err ->
                    exit(Sup, shutdown),
                    Err
            end;
        Error -> Error
    end.

-spec get_port(pid()) -> {ok, inet:port_number()} | {error, term()}.
get_port(Sup) ->
    Children = supervisor:which_children(Sup),
    case lists:keyfind(session_mgr, 1, Children) of
        {session_mgr, MgrPid, _, _} when is_pid(MgrPid) ->
            ListenerRef = erlmcp_http_session_mgr:listener_ref(MgrPid),
            case ListenerRef of
                undefined -> {error, no_listener};
                Ref -> {ok, ranch:get_port(Ref)}
            end;
        _ ->
            {error, no_session_mgr}
    end.

init([]) ->
    SupFlags = #{
        strategy => rest_for_one,
        intensity => 0,
        period => 1
    },
    {ok, {SupFlags, []}}.

%%====================================================================
%% Internal
%%====================================================================

wire_children(Sup, Config) ->
    ServerConfig = maps:with([name, version, capabilities, tools, resources,
                              prompts, handler, handlers, purpose, source,
                              docs, instructions], Config),
    case start_child(Sup, server, erlmcp_server, start_link, [ServerConfig]) of
        {ok, ServerPid} ->
            Port = maps:get(port, Config, 0),
            IdleTimeout = maps:get(idle_timeout, Config, 300000),
            EndpointPath = maps:get(endpoint_path, Config, "/mcp"),
            ReplayBufferSize = maps:get(replay_buffer_size, Config, 100),
            MgrConfig = #{
                server_pid => ServerPid,
                idle_timeout => IdleTimeout,
                server_name => maps:get(name, Config, <<"erlmcp">>),
                server_version => maps:get(version, Config, <<"0.6.0">>),
                port => Port,
                endpoint_path => EndpointPath,
                replay_buffer_size => ReplayBufferSize
            },
            case start_child(Sup, session_mgr,
                             erlmcp_http_session_mgr, start_link, [MgrConfig]) of
                {ok, _MgrPid} -> ok;
                Err -> Err
            end;
        Err -> Err
    end.

start_child(Sup, Id, Mod, Fun, Args) ->
    Spec = #{
        id => Id,
        start => {Mod, Fun, Args},
        restart => temporary,
        shutdown => 5000,
        type => worker
    },
    case supervisor:start_child(Sup, Spec) of
        {ok, Pid} -> {ok, Pid};
        Error -> Error
    end.
