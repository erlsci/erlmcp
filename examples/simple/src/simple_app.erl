-module(simple_app).

-behaviour(application).

-export([start/2, start_phase/3, stop/1]).

start(_StartType, _StartArgs) ->
    Config = #{
        name => <<"simple">>,
        version => <<"0.6.0">>,
        tools => simple_server:tools(),
        resources => simple_server:resources(),
        prompts => simple_server:prompts()
    },
    case erlmcp_stdio_sup:start_link(Config) of
        {ok, Sup} ->
            register(simple_stdio_sup, Sup),
            {ok, Sup};
        {error, _} = Err -> Err;
        ignore -> {error, supervisor_ignored}
    end.

start_phase(serve, _StartType, _Args) ->
    ok = erlmcp_stdio_sup:serve(whereis(simple_stdio_sup)),
    ok.

stop(_State) ->
    ok.
