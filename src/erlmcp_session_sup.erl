-module(erlmcp_session_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags =
        #{strategy => simple_one_for_one,
          intensity => 5,
          period => 60},
    ChildSpec =
        #{id => session,
          start => {erlmcp_server_session, start_link, []},
          restart => temporary,
          shutdown => 5000,
          type => worker},
    {ok, {SupFlags, [ChildSpec]}}.
