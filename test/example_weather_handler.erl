-module(example_weather_handler).

-export([register_all/1]).

-define(CITIES, [<<"london">>, <<"paris">>, <<"tokyo">>, <<"new_york">>]).

register_all(Server) ->
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
    }),
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
    }),
    ok.
