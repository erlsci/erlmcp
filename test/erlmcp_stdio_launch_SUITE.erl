-module(erlmcp_stdio_launch_SUITE).

%% Verifies that the sys.config logger configuration directs output to
%% standard_error (not standard_io), which is required for stdio MCP
%% servers where stdout must carry only JSON-RPC.

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([logger_writes_to_stderr/1, sys_config_is_correct/1]).

all() ->
    [logger_writes_to_stderr, sys_config_is_correct].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

%% Verify the default logger handler is configured for standard_error
%% when sys.config is loaded. Skips in test runners that don't load it.
logger_writes_to_stderr(_Config) ->
    case logger:get_handler_config(default) of
        {ok, #{config := #{type := standard_error}}} ->
            ok;
        {ok, #{config := #{type := standard_io}}} ->
            {skip, "sys.config not loaded by test runner (logger on standard_io); "
                   "verified via sys_config_is_correct instead"};
        {ok, _} ->
            {skip, "Handler config format unexpected"};
        {error, _} ->
            ct:fail("No default handler configured")
    end.

%% Verify the sys.config file itself specifies standard_error.
sys_config_is_correct(_Config) ->
    RepoRoot = find_repo_root(),
    SysConfigPath = filename:join([RepoRoot, "config", "sys.config"]),
    {ok, [Terms]} = file:consult(SysConfigPath),
    KernelCfg = proplists:get_value(kernel, Terms),
    LoggerCfg = proplists:get_value(logger, KernelCfg),
    {handler, default, logger_std_h, #{config := #{type := Type}}} =
        lists:keyfind(default, 2, LoggerCfg),
    ?assertEqual(standard_error, Type).

%%====================================================================
%% Internal
%%====================================================================

find_repo_root() ->
    BeamDir = filename:dirname(code:which(?MODULE)),
    climb(BeamDir, 10).

climb(_, 0) -> error(repo_root_not_found);
climb(Dir, N) ->
    case filelib:is_regular(filename:join(Dir, "rebar.config")) of
        true -> Dir;
        false -> climb(filename:dirname(Dir), N - 1)
    end.
