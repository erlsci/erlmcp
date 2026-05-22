-module(erlmcp_conformance_tests).

-include_lib("eunit/include/eunit.hrl").

server_scorecard_test() ->
    {Score, Results} = erlmcp_conformance:run_server_scorecard(),
    Failures = [{Level, Name} || {Level, Name, fail} <- Results],
    case Failures of
        [] -> ok;
        _ ->
            io:format("~nFailed scenarios:~n"),
            lists:foreach(fun({Level, Name}) ->
                io:format("  ~p: ~s~n", [Level, Name])
            end, Failures)
    end,
    ?assert(Score >= 87.5,
        lists:flatten(io_lib:format("Score ~.1f% < 87.5%", [Score]))).
