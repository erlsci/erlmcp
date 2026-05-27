-module(erlmcp_task_sup).

-behaviour(supervisor).

-export([start_link/0, start_task/1]).
-export([init/1]).

-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_task(map()) -> {ok, pid()} | {error, term()}.
start_task(Opts) when is_map(Opts) ->
    case supervisor:start_child(?MODULE, [Opts]) of
        {ok, Pid} -> {ok, Pid};
        {ok, Pid, _Info} -> {ok, Pid};
        Error -> Error
    end.

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags =
        #{strategy => simple_one_for_one,
          intensity => 5,
          period => 60},
    ChildSpec =
        #{id => task,
          start => {erlmcp_task, start_link, []},
          restart => temporary,
          shutdown => 5000,
          type => worker},
    {ok, {SupFlags, [ChildSpec]}}.
