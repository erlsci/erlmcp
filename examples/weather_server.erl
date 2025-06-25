-module(weather_server).
-behaviour(gen_server).

-include("erlmcp.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,
    update_temperature/2,
    add_alert_subscriber/2,
    remove_alert_subscriber/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_PORT, 8080).

%% State record
-record(state, {
    mcp_server :: pid(),
    weather_data = #{} :: #{binary() => weather_reading()},
    alert_subscribers = #{} :: #{binary() => alert_config()},
    update_timer :: reference() | undefined
}).

-type weather_reading() :: #{
    temperature := float(),
    humidity := float(),
    pressure := float(),
    timestamp := erlang:timestamp(),
    conditions := binary()
}.

-type alert_config() :: #{
    email := binary(),
    thresholds := #{atom() => {min, float()} | {max, float()}}
}.

%%====================================================================
%% API
%%====================================================================

start_link() ->
    start_link(#{}).

start_link(Options) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Options, []).

stop() ->
    gen_server:stop(?SERVER).

update_temperature(City, Temperature) ->
    gen_server:cast(?SERVER, {update_temperature, City, Temperature}).

add_alert_subscriber(Email, Thresholds) ->
    gen_server:call(?SERVER, {add_alert_subscriber, Email, Thresholds}).

remove_alert_subscriber(Email) ->
    gen_server:call(?SERVER, {remove_alert_subscriber, Email}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(Options) ->
    process_flag(trap_exit, true),
    
    %% Initialize MCP server
    TransportOpts = maps:get(transport, Options, {stdio, []}),
    Capabilities = #mcp_server_capabilities{
        resources = #mcp_capability{name = <<"resources">>, enabled = true},
        tools = #mcp_capability{name = <<"tools">>, enabled = true},
        prompts = #mcp_capability{name = <<"prompts">>, enabled = true}
    },
    
    {ok, McpServer} = erlmcp_server:start_link(TransportOpts, Capabilities),
    
    %% Register resources, tools, and prompts
    ok = setup_mcp_resources(McpServer),
    ok = setup_mcp_tools(McpServer),
    ok = setup_mcp_prompts(McpServer),
    
    %% Initialize with some demo data
    WeatherData = initialize_demo_data(),
    
    %% Start periodic updates
    Timer = erlang:send_after(60000, self(), update_weather),
    
    State = #state{
        mcp_server = McpServer,
        weather_data = WeatherData,
        update_timer = Timer
    },
    
    logger:info("Weather server started with MCP interface"),
    {ok, State}.

handle_call({add_alert_subscriber, Email, Thresholds}, _From, State) ->
    AlertConfig = #{email => Email, thresholds => Thresholds},
    NewSubscribers = maps:put(Email, AlertConfig, State#state.alert_subscribers),
    {reply, ok, State#state{alert_subscribers = NewSubscribers}};

handle_call({remove_alert_subscriber, Email}, _From, State) ->
    NewSubscribers = maps:remove(Email, State#state.alert_subscribers),
    {reply, ok, State#state{alert_subscribers = NewSubscribers}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({update_temperature, City, Temperature}, State) ->
    NewState = update_city_temperature(City, Temperature, State),
    check_alerts(City, NewState),
    %% Notify MCP subscribers
    erlmcp_server:notify_resource_updated(
        State#state.mcp_server, 
        <<"weather://", City/binary>>,
        #{<<"temperature">> => Temperature}
    ),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(update_weather, State) ->
    %% Simulate weather updates
    NewState = simulate_weather_changes(State),
    Timer = erlang:send_after(60000, self(), update_weather),
    {noreply, NewState#state{update_timer = Timer}};

handle_info({'EXIT', Pid, Reason}, #state{mcp_server = Pid} = State) ->
    logger:error("MCP server died: ~p", [Reason]),
    {stop, {mcp_server_died, Reason}, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{update_timer = Timer}) ->
    case Timer of
        undefined -> ok;
        _ -> erlang:cancel_timer(Timer)
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions - MCP Setup
%%====================================================================

setup_mcp_resources(McpServer) ->
    %% Add city weather resources
    Cities = [<<"new_york">>, <<"london">>, <<"tokyo">>, <<"sydney">>],
    lists:foreach(fun(City) ->
        Uri = <<"weather://", City/binary>>,
        erlmcp_server:add_resource(McpServer, Uri, 
            fun(_) -> get_city_weather_handler(City) end)
    end, Cities),
    
    %% Add resource template for any city
    erlmcp_server:add_resource_template(
        McpServer, 
        <<"weather://{city}">>,
        <<"Weather data for any city">>,
        fun(Uri) -> get_dynamic_city_weather_handler(Uri) end
    ),
    
    %% Add aggregated resource
    erlmcp_server:add_resource(
        McpServer,
        <<"weather://summary">>,
        fun(_) -> get_weather_summary_handler() end
    ),
    ok.

setup_mcp_tools(McpServer) ->
    %% Weather query tool
    QuerySchema = #{
        <<"type">> => <<"object">>,
        <<"properties">> => #{
            <<"city">> => #{<<"type">> => <<"string">>},
            <<"metric">> => #{
                <<"type">> => <<"string">>,
                <<"enum">> => [<<"temperature">>, <<"humidity">>, <<"pressure">>]
            }
        },
        <<"required">> => [<<"city">>, <<"metric">>]
    },
    
    erlmcp_server:add_tool_with_schema(
        McpServer,
        <<"query_weather">>,
        fun(Args) -> query_weather_tool(Args) end,
        QuerySchema
    ),
    
    %% Weather comparison tool
    CompareSchema = #{
        <<"type">> => <<"object">>,
        <<"properties">> => #{
            <<"cities">> => #{
                <<"type">> => <<"array">>,
                <<"items">> => #{<<"type">> => <<"string">>},
                <<"minItems">> => 2
            }
        },
        <<"required">> => [<<"cities">>]
    },
    
    erlmcp_server:add_tool_with_schema(
        McpServer,
        <<"compare_weather">>,
        fun(Args) -> compare_weather_tool(Args) end,
        CompareSchema
    ),
    
    %% Alert configuration tool
    AlertSchema = #{
        <<"type">> => <<"object">>,
        <<"properties">> => #{
            <<"email">> => #{<<"type">> => <<"string">>, <<"format">> => <<"email">>},
            <<"city">> => #{<<"type">> => <<"string">>},
            <<"temperature_max">> => #{<<"type">> => <<"number">>},
            <<"temperature_min">> => #{<<"type">> => <<"number">>}
        },
        <<"required">> => [<<"email">>, <<"city">>]
    },
    
    erlmcp_server:add_tool_with_schema(
        McpServer,
        <<"configure_alert">>,
        fun(Args) -> configure_alert_tool(Args) end,
        AlertSchema
    ),
    ok.

setup_mcp_prompts(McpServer) ->
    %% Weather report prompt
    ReportArgs = [
        #mcp_prompt_argument{
            name = <<"city">>,
            description = <<"City name for weather report">>,
            required = true
        },
        #mcp_prompt_argument{
            name = <<"format">>,
            description = <<"Report format: brief or detailed">>,
            required = false
        }
    ],
    
    erlmcp_server:add_prompt_with_args(
        McpServer,
        <<"weather_report">>,
        fun(Args) -> weather_report_prompt(Args) end,
        ReportArgs
    ),
    
    %% Travel advice prompt
    TravelArgs = [
        #mcp_prompt_argument{
            name = <<"destination">>,
            description = <<"Travel destination city">>,
            required = true
        },
        #mcp_prompt_argument{
            name = <<"duration">>,
            description = <<"Trip duration in days">>,
            required = true
        }
    ],
    
    erlmcp_server:add_prompt_with_args(
        McpServer,
        <<"travel_weather_advice">>,
        fun(Args) -> travel_advice_prompt(Args) end,
        TravelArgs
    ),
    ok.

%%====================================================================
%% Internal functions - Weather Logic
%%====================================================================

initialize_demo_data() ->
    Cities = [
        {<<"new_york">>, 22.5, 65.0, 1013.25, <<"partly_cloudy">>},
        {<<"london">>, 18.2, 72.0, 1009.5, <<"rainy">>},
        {<<"tokyo">>, 26.8, 78.0, 1011.0, <<"sunny">>},
        {<<"sydney">>, 19.5, 68.0, 1015.8, <<"clear">>}
    ],
    
    maps:from_list([
        {City, #{
            temperature => Temp,
            humidity => Humidity,
            pressure => Pressure,
            timestamp => erlang:timestamp(),
            conditions => Conditions
        }} || {City, Temp, Humidity, Pressure, Conditions} <- Cities
    ]).

update_city_temperature(City, Temperature, State) ->
    WeatherData = State#state.weather_data,
    Reading = maps:get(City, WeatherData, #{
        temperature => 20.0,
        humidity => 50.0,
        pressure => 1013.0,
        conditions => <<"unknown">>
    }),
    UpdatedReading = Reading#{
        temperature := Temperature,
        timestamp := erlang:timestamp()
    },
    NewWeatherData = maps:put(City, UpdatedReading, WeatherData),
    State#state{weather_data = NewWeatherData}.

simulate_weather_changes(State) ->
    WeatherData = maps:map(fun(_City, Reading) ->
        %% Random walk for temperature
        OldTemp = maps:get(temperature, Reading),
        TempChange = (rand:uniform() - 0.5) * 2.0,
        NewTemp = max(-20.0, min(45.0, OldTemp + TempChange)),
        
        %% Random walk for humidity
        OldHumidity = maps:get(humidity, Reading),
        HumidityChange = (rand:uniform() - 0.5) * 5.0,
        NewHumidity = max(0.0, min(100.0, OldHumidity + HumidityChange)),
        
        Reading#{
            temperature := NewTemp,
            humidity := NewHumidity,
            timestamp := erlang:timestamp()
        }
    end, State#state.weather_data),
    
    State#state{weather_data = WeatherData}.

check_alerts(City, State) ->
    case maps:get(City, State#state.weather_data, undefined) of
        undefined -> ok;
        Reading ->
            Temperature = maps:get(temperature, Reading),
            maps:foreach(fun(Email, Config) ->
                check_thresholds(Email, City, Temperature, Config)
            end, State#state.alert_subscribers)
    end.

check_thresholds(Email, City, Temperature, Config) ->
    Thresholds = maps:get(thresholds, Config, #{}),
    case maps:get(temperature_max, Thresholds, undefined) of
        undefined -> ok;
        MaxTemp when Temperature > MaxTemp ->
            logger:warning("Alert: ~s temperature (~.1f) exceeds max threshold (~.1f) for ~s",
                          [City, Temperature, MaxTemp, Email]);
        _ -> ok
    end,
    case maps:get(temperature_min, Thresholds, undefined) of
        undefined -> ok;
        MinTemp when Temperature < MinTemp ->
            logger:warning("Alert: ~s temperature (~.1f) below min threshold (~.1f) for ~s",
                          [City, Temperature, MinTemp, Email]);
        _ -> ok
    end.

%%====================================================================
%% Internal functions - MCP Handlers
%%====================================================================

get_city_weather_handler(City) ->
    case gen_server:call(?SERVER, {get_weather, City}, 5000) of
        {ok, Reading} ->
            format_weather_content(City, Reading);
        {error, _} ->
            #mcp_content{
                type = <<"text">>,
                text = <<"Weather data unavailable for ", City/binary>>,
                mime_type = <<"text/plain">>
            }
    end.

get_dynamic_city_weather_handler(Uri) ->
    case binary:split(Uri, <<"://">>) of
        [<<"weather">>, City] ->
            get_city_weather_handler(City);
        _ ->
            #mcp_content{
                type = <<"text">>,
                text = <<"Invalid weather URI format">>,
                mime_type = <<"text/plain">>
            }
    end.

get_weather_summary_handler() ->
    {ok, State} = gen_server:call(?SERVER, get_state),
    WeatherData = State#state.weather_data,
    
    Summary = maps:fold(fun(City, Reading, Acc) ->
        Temp = maps:get(temperature, Reading),
        [io_lib:format("~s: ~.1f°C~n", [City, Temp]) | Acc]
    end, [], WeatherData),
    
    #mcp_content{
        type = <<"text">>,
        text = iolist_to_binary(["Weather Summary:\n" | lists:reverse(Summary)]),
        mime_type = <<"text/plain">>
    }.

query_weather_tool(#{<<"city">> := City, <<"metric">> := Metric}) ->
    {ok, State} = gen_server:call(?SERVER, get_state),
    case maps:get(City, State#state.weather_data, undefined) of
        undefined ->
            #mcp_content{
                type = <<"text">>,
                text = <<"No data available for ", City/binary>>,
                mime_type = <<"text/plain">>
            };
        Reading ->
            Value = case Metric of
                <<"temperature">> -> maps:get(temperature, Reading);
                <<"humidity">> -> maps:get(humidity, Reading);
                <<"pressure">> -> maps:get(pressure, Reading)
            end,
            #mcp_content{
                type = <<"text">>,
                text = iolist_to_binary(io_lib:format("~s in ~s: ~.2f", 
                    [Metric, City, Value])),
                mime_type = <<"text/plain">>
            }
    end.

compare_weather_tool(#{<<"cities">> := Cities}) ->
    {ok, State} = gen_server:call(?SERVER, get_state),
    Comparisons = lists:map(fun(City) ->
        case maps:get(City, State#state.weather_data, undefined) of
            undefined ->
                {City, undefined};
            Reading ->
                {City, maps:get(temperature, Reading)}
        end
    end, Cities),
    
    ValidComparisons = [{C, T} || {C, T} <- Comparisons, T =/= undefined],
    
    case ValidComparisons of
        [] ->
            #mcp_content{
                type = <<"text">>,
                text = <<"No valid weather data for comparison">>,
                mime_type = <<"text/plain">>
            };
        _ ->
            Sorted = lists:sort(fun({_, T1}, {_, T2}) -> T1 > T2 end, ValidComparisons),
            ComparisonText = format_comparison(Sorted),
            #mcp_content{
                type = <<"text">>,
                text = ComparisonText,
                mime_type = <<"text/plain">>
            }
    end.

configure_alert_tool(Args) ->
    Email = maps:get(<<"email">>, Args),
    Thresholds = #{
        temperature_max => maps:get(<<"temperature_max">>, Args, undefined),
        temperature_min => maps:get(<<"temperature_min">>, Args, undefined)
    },
    
    ok = add_alert_subscriber(Email, Thresholds),
    
    #mcp_content{
        type = <<"text">>,
        text = <<"Alert configured for ", Email/binary>>,
        mime_type = <<"text/plain">>
    }.

weather_report_prompt(#{<<"city">> := City} = Args) ->
    Format = maps:get(<<"format">>, Args, <<"brief">>),
    {ok, State} = gen_server:call(?SERVER, get_state),
    
    case maps:get(City, State#state.weather_data, undefined) of
        undefined ->
            [#{
                <<"role">> => <<"assistant">>,
                <<"content">> => <<"I don't have current weather data for ", City/binary, 
                                   ". Please check if the city name is correct.">>
            }];
        Reading ->
            ReportText = case Format of
                <<"detailed">> -> format_detailed_report(City, Reading);
                _ -> format_brief_report(City, Reading)
            end,
            [#{
                <<"role">> => <<"assistant">>,
                <<"content">> => ReportText
            }]
    end.

travel_advice_prompt(#{<<"destination">> := Destination, <<"duration">> := Duration}) ->
    {ok, State} = gen_server:call(?SERVER, get_state),
    
    case maps:get(Destination, State#state.weather_data, undefined) of
        undefined ->
            [#{
                <<"role">> => <<"assistant">>,
                <<"content">> => <<"I don't have weather data for ", Destination/binary, 
                                   ". Please check the destination name.">>
            }];
        Reading ->
            Advice = generate_travel_advice(Destination, Duration, Reading),
            [#{
                <<"role">> => <<"assistant">>,
                <<"content">> => Advice
            }]
    end.

%%====================================================================
%% Internal functions - Formatting
%%====================================================================

format_weather_content(City, Reading) ->
    Text = io_lib:format(
        "Weather in ~s:\n"
        "Temperature: ~.1f°C\n"
        "Humidity: ~.0f%\n"
        "Pressure: ~.1f hPa\n"
        "Conditions: ~s\n",
        [City, 
         maps:get(temperature, Reading),
         maps:get(humidity, Reading),
         maps:get(pressure, Reading),
         maps:get(conditions, Reading)]
    ),
    #mcp_content{
        type = <<"text">>,
        text = iolist_to_binary(Text),
        mime_type = <<"text/plain">>
    }.

format_comparison(Sorted) ->
    Lines = lists:map(fun({City, Temp}) ->
        io_lib:format("~s: ~.1f°C", [City, Temp])
    end, Sorted),
    iolist_to_binary(string:join(Lines, "\n")).

format_brief_report(City, Reading) ->
    iolist_to_binary(io_lib:format(
        "Current weather in ~s: ~.1f°C, ~s",
        [City, maps:get(temperature, Reading), maps:get(conditions, Reading)]
    )).

format_detailed_report(City, Reading) ->
    iolist_to_binary(io_lib:format(
        "Detailed Weather Report for ~s:\n"
        "=====================================\n"
        "Temperature: ~.1f°C\n"
        "Humidity: ~.0f%\n"
        "Atmospheric Pressure: ~.1f hPa\n"
        "Current Conditions: ~s\n"
        "Last Updated: ~s\n",
        [City,
         maps:get(temperature, Reading),
         maps:get(humidity, Reading),
         maps:get(pressure, Reading),
         maps:get(conditions, Reading),
         format_timestamp(maps:get(timestamp, Reading))]
    )).

generate_travel_advice(Destination, Duration, Reading) ->
    Temp = maps:get(temperature, Reading),
    Conditions = maps:get(conditions, Reading),
    
    ClothingAdvice = case Temp of
        T when T < 10.0 -> "Pack warm clothes including jacket and layers.";
        T when T < 20.0 -> "Bring light jacket and long sleeves.";
        T when T < 30.0 -> "Light clothing recommended, bring sunscreen.";
        _ -> "Very hot weather, pack light breathable clothes and sun protection."
    end,
    
    ConditionsAdvice = case Conditions of
        <<"rainy">> -> " Don't forget an umbrella or raincoat.";
        <<"sunny">> -> " Sunglasses and hat recommended.";
        _ -> ""
    end,
    
    iolist_to_binary(io_lib:format(
        "Travel advice for ~s (~s days):\n"
        "Current temperature: ~.1f°C with ~s conditions.\n"
        "~s~s",
        [Destination, Duration, Temp, Conditions, ClothingAdvice, ConditionsAdvice]
    )).

format_timestamp({MegaSecs, Secs, _MicroSecs}) ->
    DateTime = calendar:now_to_datetime({MegaSecs, Secs, 0}),
    {{Y, M, D}, {H, Mi, S}} = DateTime,
    io_lib:format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B",
                  [Y, M, D, H, Mi, S]).

%%====================================================================
%% gen_server API for handlers
%%====================================================================

handle_call({get_weather, City}, _From, State) ->
    case maps:get(City, State#state.weather_data, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Reading -> {reply, {ok, Reading}, State}
    end;

handle_call(get_state, _From, State) ->
    {reply, {ok, State}, State}.