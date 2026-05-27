-module(erlmcp_stdio_sup).

-behaviour(supervisor).

-export([start_link/1, serve/1]).
-export([init/1]).

%% one_for_all + temporary + intensity 0: all three (server, transport,
%% session) live and die as a unit. Any child death terminates the
%% supervisor — no auto-restart. A stdio server is single-use; when
%% stdin closes, the process exits.

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
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

-spec serve(pid()) -> ok | {error, term()}.
serve(Sup) ->
    Children = supervisor:which_children(Sup),
    case lists:keyfind(transport, 1, Children) of
        {transport, Pid, _, _} when is_pid(Pid) ->
            erlmcp_transport_stdio:serve(Pid);
        _ ->
            {error, transport_not_found}
    end.

init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 0,
        period => 1
    },
    {ok, {SupFlags, []}}.

%%====================================================================
%% Internal
%%====================================================================

wire_children(Sup, Config) ->
    ServerConfig = maps:with([name, version, capabilities, tools, resources,
                              prompts, handler, handlers], Config),
    case start_child(Sup, server, erlmcp_server, start_link, [ServerConfig]) of
        {ok, ServerPid} ->
            TransportConfig = maps:without([name, version, capabilities, tools,
                                            resources, prompts, handler, handlers],
                                           Config),
            case start_child(Sup, transport, erlmcp_transport_stdio, start_link,
                             [TransportConfig]) of
                {ok, TransportPid} ->
                    Responder = erlmcp_reply:new_device(TransportPid),
                    SessionConfig = #{
                        server => ServerPid,
                        responder => Responder,
                        name => maps:get(name, Config, <<"erlmcp">>),
                        version => maps:get(version, Config, <<"0.6.0">>)
                    },
                    case start_child(Sup, session, erlmcp_server_session, start_link,
                                     [SessionConfig]) of
                        {ok, SessionPid} ->
                            erlmcp_transport_stdio:set_session(TransportPid, SessionPid),
                            ok;
                        Err -> Err
                    end;
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
        {ok, Pid, _} -> {ok, Pid};
        Error -> Error
    end.
