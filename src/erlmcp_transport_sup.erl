-module(erlmcp_transport_sup).

-behaviour(supervisor).

-export([start_link/0, start_child/3]).
-export([init/1]).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_child(atom(), atom(), map()) -> {ok, pid()} | {error, term()}.
start_child(TransportId, Type, Config) ->
    % Determine the appropriate transport module
    Module =
        case Type of
            stdio ->
                erlmcp_transport_stdio_new;
            tcp ->
                erlmcp_transport_tcp_new;
            http ->
                erlmcp_transport_http_new
        end,

    ChildSpec =
        #{id => TransportId,
          start => {Module, start_link, [TransportId, Config]},
          restart => temporary,  % Don't auto-restart - let registry handle failures
          shutdown => 5000,
          type => worker,
          modules => [Module]},
    supervisor:start_child(?MODULE, ChildSpec).

%%====================================================================
%% supervisor callbacks
%%====================================================================

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags =
        #{strategy => one_for_one,  % Transport failures are isolated
          intensity => 5,
          period => 60},

    % Start with empty child specs - transports are added dynamically
    ChildSpecs = [],

    {ok, {SupFlags, ChildSpecs}}.
