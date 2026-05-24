-module(erlmcp_client_task_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([
    client_task_poll_result/1,
    client_task_list/1,
    client_task_cancel/1,
    client_task_capability_gating/1
]).

all() ->
    [client_task_poll_result, client_task_list,
     client_task_cancel, client_task_capability_gating].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Config.

end_per_suite(_Config) ->
    application:stop(erlmcp),
    ok.

init_per_testcase(_TC, Config) ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => SBridge,
        name => <<"task-test">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    ok = erlmcp:add_tool(Server, #{
        name => <<"slow_compute">>,
        description => <<"Slow computation">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"n">>, erlmcp_schema:number(), [required])
        ]),
        task_support => optional,
        handler => fun(#{<<"n">> := N}, _Ctx) ->
            timer:sleep(trunc(N)),
            {ok, erlmcp:text(<<"done">>)}
        end
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"task-client">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    [{server, Server}, {client, Client} | Config].

end_per_testcase(_TC, Config) ->
    catch erlmcp_client_session:stop(?config(client, Config)),
    catch gen_statem:stop(?config(server, Config)),
    ok.

bridge(Peer) ->
    receive
        {peer, Pid} -> bridge(Pid);
        {send, Data} when is_pid(Peer) ->
            gen_statem:cast(Peer, {transport_data, Data}),
            bridge(Peer);
        _ -> bridge(Peer)
    end.

%%====================================================================
%% Tests
%%====================================================================

client_task_poll_result(Config) ->
    Client = ?config(client, Config),
    {ok, CallResult} = erlmcp_client_session:call_tool(Client,
        <<"slow_compute">>, #{<<"n">> => 100},
        #{progress_token => <<"tok">>,
          task => true}),
    TaskId = maps:get(<<"taskId">>, CallResult),
    ?assert(is_binary(TaskId)),
    {ok, Status} = erlmcp_client_session:get_task(Client, TaskId),
    ?assert(is_binary(maps:get(<<"status">>, Status))),
    timer:sleep(300),
    {ok, Result} = erlmcp_client_session:get_task_result(Client, TaskId),
    ?assert(is_map(Result)).

client_task_list(Config) ->
    Client = ?config(client, Config),
    {ok, CallResult} = erlmcp_client_session:call_tool(Client,
        <<"slow_compute">>, #{<<"n">> => 2000},
        #{task => true}),
    ?assert(maps:is_key(<<"taskId">>, CallResult)),
    timer:sleep(100),
    {ok, ListResult} = erlmcp_client_session:list_tasks(Client),
    Tasks = maps:get(<<"tasks">>, ListResult),
    ?assert(length(Tasks) >= 1).

client_task_cancel(Config) ->
    Client = ?config(client, Config),
    {ok, CallResult} = erlmcp_client_session:call_tool(Client,
        <<"slow_compute">>, #{<<"n">> => 5000},
        #{task => true}),
    TaskId = maps:get(<<"taskId">>, CallResult),
    timer:sleep(100),
    ok = erlmcp_client_session:cancel_task(Client, TaskId),
    timer:sleep(100),
    {ok, Status} = erlmcp_client_session:get_task(Client, TaskId),
    ?assertEqual(<<"cancelled">>, maps:get(<<"status">>, Status)).

client_task_capability_gating(_Config) ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Server} = erlmcp_server_session:start_link(#{
        transport => SBridge,
        name => <<"no-tasks">>, version => <<"1.0">>,
        capabilities => #{}
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge,
        owner => self(),
        name => <<"test">>, version => <<"1.0">>
    }),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ?assertMatch({error, {capability_not_supported, <<"tasks">>}},
                 erlmcp_client_session:list_tasks(Client)),
    ?assertMatch({error, {capability_not_supported, <<"tasks">>}},
                 erlmcp_client_session:get_task(Client, <<"x">>)),
    erlmcp_client_session:stop(Client),
    gen_statem:stop(Server).
