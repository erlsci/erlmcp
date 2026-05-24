-module(erlmcp_sup).

-behaviour(supervisor).

-export([start_link/0, start_server/2, stop_server/1, start_transport/3, stop_transport/1,
         start_stdio_server/0, start_stdio_server/1, stop_stdio_server/0]).
-export([init/1]).

-include("erlmcp.hrl").

-define(SERVER, ?MODULE).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% Server management API
-spec start_server(atom(), #{}) -> {ok, pid()} | {error, term()}.
start_server(ServerId, Config) ->
    Opts = Config#{name => atom_to_binary(ServerId, utf8)},
    case supervisor:start_child(erlmcp_server_sup, [Opts]) of
        {ok, ServerPid} ->
            % Register with registry
            ok = erlmcp_registry:register_server(ServerId, ServerPid, Config),
            {ok, ServerPid};
        {error, _} = Error ->
            Error
    end.

-spec stop_server(atom()) -> ok | {error, term()}.
stop_server(ServerId) ->
    case erlmcp_registry:find_server(ServerId) of
        {ok, {ServerPid, _Config}} ->
            ok = erlmcp_registry:unregister_server(ServerId),
            supervisor:terminate_child(erlmcp_server_sup, ServerPid);
        {error, not_found} ->
            ok
    end.

%% Transport management API
-spec start_transport(atom(), atom(), #{}) -> {ok, pid()} | {error, term()}.
start_transport(TransportId, Type, Config) ->
    case erlmcp_transport_sup:start_child(TransportId, Type, Config) of
        {ok, TransportPid} ->
            TransportConfig = Config#{type => Type},
            ok = erlmcp_registry:register_transport(TransportId, TransportPid, TransportConfig),
            {ok, TransportPid};
        {error, _} = Error ->
            Error
    end.

-spec stop_transport(atom()) -> ok | {error, term()}.
stop_transport(TransportId) ->
    case erlmcp_registry:find_transport(TransportId) of
        {ok, {_TransportPid, _Config}} ->
            ok = erlmcp_registry:unregister_transport(TransportId),
            supervisor:terminate_child(erlmcp_transport_sup, TransportId);
        {error, not_found} ->
            ok
    end.

%% Legacy stdio server support (for backward compatibility)
-spec start_stdio_server() -> {ok, pid()} | {error, term()}.
start_stdio_server() ->
    start_stdio_server(#{}).

-spec start_stdio_server(map()) -> {ok, pid()} | {error, term()}.
start_stdio_server(_Options) ->
    {error, removed}.

-spec stop_stdio_server() -> ok.
stop_stdio_server() ->
    _ = stop_transport(default_stdio_transport),
    _ = stop_server(default_stdio_server),
    ok.

%%====================================================================
%% supervisor callbacks
%%====================================================================

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags =
        #{strategy => one_for_all,
          intensity => 3,
          period => 60},

    % Core infrastructure components
    ChildSpecs =
        [% Registry - central message router
         #{id => erlmcp_registry,
           start => {erlmcp_registry, start_link, []},
           restart => permanent,
           shutdown => 5000,
           type => worker,
           modules => [erlmcp_registry]},
         % Server supervisor - manages server instances
         #{id => erlmcp_server_sup,
           start => {erlmcp_server_sup, start_link, []},
           restart => permanent,
           shutdown => infinity,
           type => supervisor,
           modules => [erlmcp_server_sup]},
         % Transport supervisor - manages transport instances
         #{id => erlmcp_transport_sup,
           start => {erlmcp_transport_sup, start_link, []},
           restart => permanent,
           shutdown => infinity,
           type => supervisor,
           modules => [erlmcp_transport_sup]},
         % Task supervisor - manages long-running tasks
         #{id => erlmcp_task_sup,
           start => {erlmcp_task_sup, start_link, []},
           restart => permanent,
           shutdown => infinity,
           type => supervisor,
           modules => [erlmcp_task_sup]}],

    {ok, {SupFlags, ChildSpecs}}.
