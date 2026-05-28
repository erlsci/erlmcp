-module(calculator_app).

-behaviour(application).

-export([start/2, start_phase/3, stop/1]).

start(_StartType, _StartArgs) ->
    Config = #{
        name => <<"calculator">>,
        version => <<"0.6.0">>,
        handler => calculator_server,
        tools => [erlmcp:make_directory_tool(),
                  calculator_server:slow_tool_spec(),
                  calculator_server:explain_tool_spec()]
    },
    case erlmcp_stdio_sup:start_link(Config) of
        {ok, Sup} ->
            register(calculator_stdio_sup, Sup),
            {ok, Sup};
        {error, _} = Err -> Err;
        ignore -> {error, supervisor_ignored}
    end.

start_phase(serve, _StartType, _Args) ->
    ok = erlmcp_stdio_sup:serve(whereis(calculator_stdio_sup)),
    ok.

stop(_State) ->
    ok.
