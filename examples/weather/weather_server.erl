-module(weather_server).

%% A runnable weather MCP server demonstrating:
%%   - Resources (static + handler-backed)
%%   - Resource templates with completion
%%   - Subscriptions (notify on resource update)
%%   - Prompts with arguments and completion
%%   - Logging
%%   - Multiple transports (stdio + tcp)

-export([start_stdio/0, start_stdio/1, start_tcp/2, stop/1]).
-export([register_all/1]).

-define(CITIES, [<<"london">>, <<"paris">>, <<"tokyo">>, <<"new_york">>]).

-spec start_stdio() -> {ok, #{server := pid(), transport := pid()}}.
start_stdio() ->
    start_stdio(#{}).

-spec start_stdio(map()) -> {ok, #{server := pid(), transport := pid()}}.
start_stdio(Config) ->
    {ok, #{server := Server} = Result} =
        erlmcp:start_stdio_setup(weather, Config),
    register_all(Server),
    {ok, Result}.

-spec start_tcp(inet:hostname(), inet:port_number()) ->
    {ok, #{server := pid(), transport := pid()}}.
start_tcp(Host, Port) ->
    {ok, #{server := Server} = Result} =
        erlmcp:start_tcp_setup(weather, #{}, #{host => Host, port => Port}),
    register_all(Server),
    {ok, Result}.

-spec stop(pid()) -> ok.
stop(Server) ->
    gen_statem:stop(Server).

-spec register_all(pid()) -> ok.
register_all(Server) ->
    register_tools(Server),
    register_resources(Server),
    register_prompts(Server),
    ok.

%%====================================================================
%% Tools
%%====================================================================

register_tools(Server) ->
    ok = erlmcp:add_tool(Server, #{
        name => <<"get_weather">>,
        description => <<"Get current weather for a city">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"city">>, erlmcp_schema:string(), [required])
        ]),
        category => <<"weather">>,
        handler => fun(#{<<"city">> := City}, _Ctx) ->
            {ok, erlmcp:text(weather_text(City))}
        end
    }).

%%====================================================================
%% Resources — static, template, completion
%%====================================================================

register_resources(Server) ->
    ok = erlmcp:add_resource(Server, #{
        uri => <<"weather://current/london">>,
        name => <<"London Weather">>,
        description => <<"Current weather for London">>,
        mime_type => <<"application/json">>,
        handler => fun(_Ctx) ->
            {ok, #{<<"uri">> => <<"weather://current/london">>,
                   <<"mimeType">> => <<"application/json">>,
                   <<"text">> => <<"{\"temp\":15,\"condition\":\"cloudy\"}">>}}
        end
    }),
    ok = erlmcp:add_resource_template(Server, #{
        uri_template => <<"weather://current/{city}">>,
        name => <<"City Weather">>,
        description => <<"Current weather for any city">>,
        mime_type => <<"application/json">>,
        handler => fun(#{<<"city">> := City}, _Ctx) ->
            Text = <<"{\"city\":\"", City/binary, "\",\"temp\":20}">>,
            {ok, #{<<"uri">> => <<"weather://current/", City/binary>>,
                   <<"mimeType">> => <<"application/json">>,
                   <<"text">> => Text}}
        end,
        completions => #{
            <<"city">> => fun(Prefix) ->
                [C || C <- ?CITIES, binary:match(C, Prefix) =/= nomatch]
            end
        }
    }).

%%====================================================================
%% Prompts — arguments, completion
%%====================================================================

register_prompts(Server) ->
    ok = erlmcp:add_prompt(Server, #{
        name => <<"weather_report">>,
        description => <<"Generate a weather report for a city">>,
        arguments => [
            #{name => <<"city">>, description => <<"City name">>, required => true},
            #{name => <<"units">>, description => <<"Temperature units (c/f)">>}
        ],
        handler => fun(#{<<"city">> := City} = Args, _Ctx) ->
            Units = maps:get(<<"units">>, Args, <<"c">>),
            {ok, [
                #{<<"role">> => <<"user">>,
                  <<"content">> => #{
                      <<"type">> => <<"text">>,
                      <<"text">> => <<"Give me a weather report for ",
                                      City/binary, " in ", Units/binary, " units.">>
                  }}
            ]}
        end,
        completions => #{
            <<"city">> => fun(Prefix) ->
                [C || C <- ?CITIES, binary:match(C, Prefix) =/= nomatch]
            end,
            <<"units">> => fun(_) -> [<<"c">>, <<"f">>] end
        }
    }).

%%====================================================================
%% Internal — mock weather data
%%====================================================================

weather_text(City) ->
    Temp = 15 + erlang:phash2(City, 20),
    Conditions = [<<"sunny">>, <<"cloudy">>, <<"rainy">>, <<"windy">>],
    Condition = lists:nth(1 + erlang:phash2(City, 4), Conditions),
    <<City/binary, ": ", (integer_to_binary(Temp))/binary,
      "°C, ", Condition/binary>>.
