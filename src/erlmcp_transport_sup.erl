-module(erlmcp_transport_sup).

-behaviour(supervisor).

-export([start_link/0, start_child/3]).
-export([init/1]).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_child(atom(), atom(), map()) -> {ok, pid()} | {error, term()}.
start_child(TransportId, Type, Config) ->
    {Module, Args} = case Type of
        stdio -> {erlmcp_transport_stdio, [Config]};
        tcp -> {erlmcp_transport_tcp, [Config]};
        http -> {erlmcp_transport_http, [Config]}
    end,
    ChildSpec =
        #{id => TransportId,
          start => {Module, start_link, Args},
          restart => temporary,
          shutdown => 5000,
          type => worker,
          modules => [Module]},
    case supervisor:start_child(?MODULE, ChildSpec) of
        {ok, Pid} -> {ok, Pid};
        {ok, Pid, _Info} -> {ok, Pid};
        Error -> Error
    end.

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
