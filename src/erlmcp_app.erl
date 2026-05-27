-module(erlmcp_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    case erlmcp_sup:start_link() of
        {ok, Pid} -> {ok, Pid};
        {error, _} = Err -> Err;
        ignore -> {error, supervisor_ignored}
    end.

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
