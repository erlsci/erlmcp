-module(erlmcp_example_disc_SUITE).

%% DISC-1/2/3 invariant checks for each example server.

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([disc_calculator/1, disc_simple/1, disc_weather/1]).

all() ->
    [disc_calculator, disc_simple, disc_weather].

init_per_testcase(_TC, Config) ->
    Config.

end_per_testcase(_TC, _Config) ->
    ok.

disc_calculator(_Config) ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"calc-disc">>, version => <<"1.0">>,
        handler => calculator_server
    }),
    ok = erlmcp:add_tool(Server, erlmcp:make_directory_tool()),
    ok = erlmcp:add_tool(Server, calculator_server:slow_tool_spec()),
    ok = erlmcp:add_tool(Server, calculator_server:explain_tool_spec()),
    check_disc_invariants(Server),
    gen_server:stop(Server).

disc_simple(_Config) ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"simple-disc">>, version => <<"1.0">>
    }),
    simple_server:register_all(Server),
    check_disc_invariants(Server),
    gen_server:stop(Server).

disc_weather(_Config) ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"weather-disc">>, version => <<"1.0">>
    }),
    weather_server:register_all(Server),
    check_disc_invariants(Server),
    gen_server:stop(Server).

%%====================================================================
%% Shared DISC-1/2/3 checks
%%====================================================================

check_disc_invariants(Server) ->
    Tools = erlmcp:conformance_tools(Server),
    check_disc1(Tools),
    check_disc2(Tools),
    check_disc3(Tools).

check_disc1(Tools) ->
    lists:foreach(fun(T) ->
        Name = maps:get(name, T),
        ?assertNotEqual(<<>>, maps:get(category, T, <<>>),
            lists:flatten(io_lib:format("~s missing category", [Name]))),
        ?assertNotEqual(<<>>, maps:get(when_to_use, T, <<>>),
            lists:flatten(io_lib:format("~s missing when_to_use", [Name])))
    end, Tools).

check_disc2(Tools) ->
    Names = [maps:get(name, T) || T <- Tools],
    AllNext = lists:flatten([maps:get(next, T, []) || T <- Tools]),
    Dangling = [N || N <- AllNext, not lists:member(N, Names)],
    ?assertEqual([], Dangling).

check_disc3(Tools) ->
    ToolNames = [maps:get(name, T) || T <- Tools],
    Explicit = [maps:get(name, T) || T <- Tools,
                    maps:get(entry_point, T, false) =:= true],
    EntryPoints = case Explicit of
        [] ->
            AllNext = lists:usort(lists:flatten(
                [maps:get(next, T, []) || T <- Tools])),
            [N || N <- ToolNames, not lists:member(N, AllNext)];
        _ -> Explicit
    end,
    AllSet = sets:from_list(ToolNames),
    NextMap = maps:from_list([{maps:get(name, T), maps:get(next, T, [])}
                              || T <- Tools]),
    Reachable = bfs(EntryPoints, NextMap, sets:new()),
    Unreachable = sets:to_list(sets:subtract(AllSet, Reachable)),
    ?assertEqual([], Unreachable).

bfs([], _NextMap, Visited) -> Visited;
bfs([Node | Queue], NextMap, Visited) ->
    case sets:is_element(Node, Visited) of
        true -> bfs(Queue, NextMap, Visited);
        false ->
            bfs(Queue ++ maps:get(Node, NextMap, []),
                NextMap, sets:add_element(Node, Visited))
    end.
