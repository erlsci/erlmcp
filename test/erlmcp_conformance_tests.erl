-module(erlmcp_conformance_tests).

-include_lib("eunit/include/eunit.hrl").

server_scorecard_test() ->
    {Score, Results} = erlmcp_conformance:run_server_scorecard(),
    Failures = [{Level, Name} || {Level, Name, fail} <- Results],
    case Failures of
        [] -> ok;
        _ ->
            io:format("~nFailed server scenarios:~n"),
            lists:foreach(fun({Level, Name}) ->
                io:format("  ~p: ~s~n", [Level, Name])
            end, Failures)
    end,
    ?assert(Score >= 87.5,
        lists:flatten(io_lib:format("Server score ~.1f% < 87.5%", [Score]))).

client_scorecard_test() ->
    {Score, Results} = erlmcp_conformance:run_client_scorecard(),
    Failures = [{Level, Name} || {Level, Name, fail} <- Results],
    case Failures of
        [] -> ok;
        _ ->
            io:format("~nFailed client scenarios:~n"),
            lists:foreach(fun({Level, Name}) ->
                io:format("  ~p: ~s~n", [Level, Name])
            end, Failures)
    end,
    ?assert(Score >= 87.5,
        lists:flatten(io_lib:format("Client score ~.1f% < 87.5%", [Score]))).

transport_scorecard_test() ->
    {Score, Results} = erlmcp_conformance:run_transport_scorecard(),
    Failures = [{Level, Name} || {Level, Name, fail} <- Results],
    case Failures of
        [] -> ok;
        _ ->
            io:format("~nFailed transport scenarios:~n"),
            lists:foreach(fun({Level, Name}) ->
                io:format("  ~p: ~s~n", [Level, Name])
            end, Failures)
    end,
    ?assert(Score >= 87.5,
        lists:flatten(io_lib:format("Transport score ~.1f% < 87.5%", [Score]))).
