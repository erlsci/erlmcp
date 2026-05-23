-module(erlmcp_server_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%====================================================================
%% supervisor callbacks
%%====================================================================

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags =
        #{strategy => simple_one_for_one,  % Dynamic server instances
          intensity => 5,
          period => 60},

    % Template child spec for server instances
    ChildSpecs =
        [#{id => erlmcp_server_session,
           start => {erlmcp_server_session, start_link, []},
           restart => temporary,
           shutdown => 5000,
           type => worker,
           modules => [erlmcp_server_session]}],

    {ok, {SupFlags, ChildSpecs}}.
