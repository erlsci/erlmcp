%% -*- coding: utf-8 -*-
-module(weather_server).

%% A runnable weather MCP server demonstrating:
%%   - Resources (static + handler-backed)
%%   - Resource templates with completion
%%   - Prompts with arguments and completion
%%   - Discoverability (full wayfinding, directory tool)
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
    ok = erlmcp:add_tool(Server, erlmcp:make_directory_tool()),
    register_tools(Server),
    register_resources(Server),
    register_prompts(Server),
    ok.

%%====================================================================
%% Tools — full discoverability wayfinding
%%====================================================================

register_tools(Server) ->
    ok = erlmcp:add_tool(Server, #{
        name => <<"get_weather">>,
        description => <<"Get current weather for a city">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"city">>, erlmcp_schema:string(), [required])
        ]),
        category => <<"weather">>,
        when_to_use => <<"When you need current weather conditions for a city">>,
        returns => <<"Temperature, condition, and city name">>,
        summary => <<"Looks up current weather using mock data">>,
        next => [<<"get_forecast">>],
        entry_point => true,
        icons => emoji_icon(<<"🌤"/utf8>>),
        annotations => #{readOnlyHint => true},
        handler => fun(#{<<"city">> := City}, _Ctx) ->
            {ok, erlmcp:text(weather_text(City))}
        end
    }),
    ok = erlmcp:add_tool(Server, #{
        name => <<"get_forecast">>,
        description => <<"Get a multi-day weather forecast for a city">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"city">>, erlmcp_schema:string(), [required]),
            erlmcp_schema:field(<<"days">>, erlmcp_schema:integer([{min, 1}, {max, 7}]),
                [{default, 3}])
        ]),
        category => <<"weather">>,
        when_to_use => <<"When you need a multi-day forecast">>,
        returns => <<"A list of daily forecasts">>,
        summary => <<"Generates mock forecast data for the requested days">>,
        next => [<<"get_weather">>],
        icons => emoji_icon(<<"📅"/utf8>>),
        annotations => #{readOnlyHint => true},
        handler => fun(#{<<"city">> := City} = Args, _Ctx) ->
            Days = maps:get(<<"days">>, Args, 3),
            {ok, erlmcp:text(forecast_text(City, Days))}
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
      "°C, "/utf8, Condition/binary>>.

forecast_text(City, Days) ->
    Lines = [begin
        Temp = 15 + erlang:phash2({City, D}, 20),
        <<"Day ", (integer_to_binary(D))/binary, ": ",
          (integer_to_binary(Temp))/binary, "°C"/utf8>>
    end || D <- lists:seq(1, Days)],
    iolist_to_binary(lists:join(<<"\n">>, Lines)).

%%====================================================================
%% Internal — icons
%%====================================================================

%% Build a spec-conformant MCP `Icon` from an emoji glyph. See the matching
%% helper in calculator_server for the rationale: MCP `Icon` requires a `src`
%% URI, so we render the emoji into an inline SVG and embed it as a base64
%% `data:` URI rather than inventing a non-standard emoji field. `Emoji` must
%% be valid UTF-8 (use the `/utf8` literal modifier).
-spec emoji_icon(binary()) -> [map()].
emoji_icon(Emoji) when is_binary(Emoji) ->
    Svg = <<"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" "
            "viewBox=\"0 0 48 48\"><text x=\"24\" y=\"36\" font-size=\"34\" "
            "text-anchor=\"middle\">", Emoji/binary, "</text></svg>">>,
    Src = <<"data:image/svg+xml;base64,", (base64:encode(Svg))/binary>>,
    [#{<<"src">> => Src,
       <<"mimeType">> => <<"image/svg+xml">>,
       <<"sizes">> => [<<"any">>]}].
