-module(weather_app).

-behaviour(application).

-export([start/2, start_phase/3, stop/1]).

start(_StartType, _StartArgs) ->
    Config = #{
        name => <<"weather">>,
        version => <<"0.6.0">>,
        tools => weather_server:tools(),
        resources => weather_server:resources(),
        prompts => weather_server:prompts()
    },
    case erlmcp_stdio_sup:start_link(Config) of
        {ok, Sup} ->
            ok = erlmcp_server:register_resource_template(
                     get_server(Sup), weather_server:resource_template()),
            register(weather_stdio_sup, Sup),
            {ok, Sup};
        {error, _} = Err -> Err;
        ignore -> {error, supervisor_ignored}
    end.

start_phase(serve, _StartType, _Args) ->
    ok = erlmcp_stdio_sup:serve(whereis(weather_stdio_sup)),
    ok.

stop(_State) ->
    ok.

get_server(Sup) ->
    Children = supervisor:which_children(Sup),
    {server, Pid, _, _} = lists:keyfind(server, 1, Children),
    Pid.
