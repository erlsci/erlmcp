-module(erlmcp_stdio_launch_SUITE).

%% Verifies the stdio transport configuration for Claude Desktop:
%% - sys.config directs logs to standard_error
%% - run.sh scripts load sys.config via -config
%% - transport source targets the user I/O server
%%
%% The real round-trip (stdin→server→stdout over a pipe) is verified by
%% test/scripts/test_stdio_roundtrip.sh, run outside the VM — launching
%% a child Erlang VM from inside an existing one confuses the user I/O
%% server's fd wiring.

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([sys_config_is_correct/1, run_sh_has_config_flag/1,
         user_device_in_transport/1]).

all() ->
    [sys_config_is_correct, run_sh_has_config_flag, user_device_in_transport].

init_per_suite(Config) ->
    [{repo_root, find_repo_root()} | Config].

end_per_suite(_Config) ->
    ok.

sys_config_is_correct(Config) ->
    RepoRoot = ?config(repo_root, Config),
    SysConfigPath = filename:join([RepoRoot, "config", "sys.config"]),
    {ok, [Terms]} = file:consult(SysConfigPath),
    KernelCfg = proplists:get_value(kernel, Terms),
    LoggerCfg = proplists:get_value(logger, KernelCfg),
    {handler, default, logger_std_h, #{config := #{type := Type}}} =
        lists:keyfind(default, 2, LoggerCfg),
    ?assertEqual(standard_error, Type).

run_sh_has_config_flag(Config) ->
    RepoRoot = ?config(repo_root, Config),
    Scripts = filelib:wildcard(
        filename:join([RepoRoot, "examples", "*", "run.sh"])),
    ?assert(length(Scripts) >= 3, "Expected at least 3 run.sh scripts"),
    lists:foreach(fun(Script) ->
        {ok, Content} = file:read_file(Script),
        ?assert(binary:match(Content, <<"-config config/sys">>) =/= nomatch,
            ["run.sh missing -config: ", Script])
    end, Scripts).

user_device_in_transport(Config) ->
    RepoRoot = ?config(repo_root, Config),
    SrcPath = filename:join([RepoRoot, "src", "erlmcp_transport_stdio.erl"]),
    {ok, Content} = file:read_file(SrcPath),
    ?assert(binary:match(Content, <<"io:get_line(user,">>) =/= nomatch,
        "transport must read via io:get_line(user, ...)"),
    ?assert(binary:match(Content, <<"io:put_chars(user,">>) =/= nomatch,
        "transport must write via io:put_chars(user, ...)").

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
