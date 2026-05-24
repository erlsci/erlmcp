-module(erlmcp_task_tests).

-include_lib("eunit/include/eunit.hrl").

make_ctx() ->
    erlmcp_ctx:new(#{session => self(), transport => self(), request_id => 1}).

start_task(Handler) ->
    {ok, Pid} = erlmcp_task:start_link(#{
        id => <<"test-task">>,
        session => self(),
        handler => Handler,
        args => #{},
        ctx => make_ctx()
    }),
    unlink(Pid),
    Pid.

task_lifecycle_test() ->
    Pid = start_task(fun(_, _) -> {ok, erlmcp:text(<<"done">>)} end),
    timer:sleep(100),
    {ok, Status} = erlmcp_task:get_status(Pid),
    ?assertEqual(<<"completed">>, maps:get(<<"status">>, Status)),
    {ok, _Result} = erlmcp_task:get_result(Pid),
    gen_server:stop(Pid).

task_running_status_test() ->
    Pid = start_task(fun(_, _) -> timer:sleep(5000), {ok, erlmcp:text(<<"late">>)} end),
    timer:sleep(50),
    {ok, Status} = erlmcp_task:get_status(Pid),
    ?assertEqual(<<"running">>, maps:get(<<"status">>, Status)),
    ?assertEqual({error, not_ready}, erlmcp_task:get_result(Pid)),
    gen_server:stop(Pid).

task_cancel_test() ->
    Pid = start_task(fun(_, _) -> timer:sleep(5000), {ok, erlmcp:text(<<"late">>)} end),
    timer:sleep(50),
    ok = erlmcp_task:cancel(Pid),
    {ok, Status} = erlmcp_task:get_status(Pid),
    ?assertEqual(<<"cancelled">>, maps:get(<<"status">>, Status)),
    ?assertEqual({error, cancelled}, erlmcp_task:get_result(Pid)),
    gen_server:stop(Pid).

task_cancel_completed_test() ->
    Pid = start_task(fun(_, _) -> {ok, erlmcp:text(<<"fast">>)} end),
    timer:sleep(100),
    ok = erlmcp_task:cancel(Pid),
    {ok, Status} = erlmcp_task:get_status(Pid),
    ?assertEqual(<<"completed">>, maps:get(<<"status">>, Status)),
    gen_server:stop(Pid).

task_error_result_test() ->
    Pid = start_task(fun(_, _) -> {error, -32000, <<"custom error">>} end),
    timer:sleep(100),
    {ok, Status} = erlmcp_task:get_status(Pid),
    ?assertEqual(<<"failed">>, maps:get(<<"status">>, Status)),
    ?assertMatch({error, {failed, _}}, erlmcp_task:get_result(Pid)),
    gen_server:stop(Pid).

task_crash_test() ->
    Pid = start_task(fun(_, _) -> error(boom) end),
    timer:sleep(100),
    {ok, Status} = erlmcp_task:get_status(Pid),
    ?assertEqual(<<"failed">>, maps:get(<<"status">>, Status)),
    gen_server:stop(Pid).

task_progress_test() ->
    Pid = start_task(fun(_, Ctx) ->
        erlmcp_ctx:report_progress(Ctx, 0.5, <<"halfway">>),
        timer:sleep(200),
        {ok, erlmcp:text(<<"done">>)}
    end),
    timer:sleep(50),
    receive {send_notification, _, _} -> ok after 1000 -> ok end,
    gen_server:stop(Pid).

task_progress_via_cast_test() ->
    Pid = start_task(fun(_, _) -> timer:sleep(5000), {ok, erlmcp:text(<<"x">>)} end),
    timer:sleep(50),
    gen_server:cast(Pid, {progress, 0.75, <<"three quarters">>}),
    timer:sleep(50),
    {ok, Status} = erlmcp_task:get_status(Pid),
    ?assertEqual(0.75, maps:get(<<"progress">>, Status)),
    gen_server:stop(Pid).

task_unknown_call_test() ->
    Pid = start_task(fun(_, _) -> timer:sleep(5000), {ok, erlmcp:text(<<"x">>)} end),
    ?assertEqual({error, unknown_request}, gen_server:call(Pid, bogus)),
    gen_server:stop(Pid).

task_unknown_cast_test() ->
    Pid = start_task(fun(_, _) -> timer:sleep(5000), {ok, erlmcp:text(<<"x">>)} end),
    gen_server:cast(Pid, unknown),
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    gen_server:stop(Pid).

task_unknown_info_test() ->
    Pid = start_task(fun(_, _) -> timer:sleep(5000), {ok, erlmcp:text(<<"x">>)} end),
    Pid ! unknown,
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    gen_server:stop(Pid).

task_handler_3_arity_test() ->
    Pid = start_task(fun(_, _, TaskPid) ->
        gen_server:cast(TaskPid, {progress, 0.5, <<"half">>}),
        {ok, erlmcp:text(<<"done">>)}
    end),
    timer:sleep(100),
    {ok, Status} = erlmcp_task:get_status(Pid),
    ?assertEqual(<<"completed">>, maps:get(<<"status">>, Status)),
    gen_server:stop(Pid).

task_cancel_no_worker_test() ->
    Pid = start_task(fun(_, _) -> {ok, erlmcp:text(<<"fast">>)} end),
    timer:sleep(200),
    ok = erlmcp_task:cancel(Pid),
    gen_server:stop(Pid).
