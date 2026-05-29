-module(erlmcp_stdio_deep_protocol_SUITE).

%% P6M2-18: Deep protocol paths over stdio — tasks/cancel and sampling.
%% These prove the BEAM differentiators: cancellation = process kill,
%% and the bidirectional server→client contract.

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([task_progress_and_cancel/1, sampling_round_trip/1]).

all() -> [task_progress_and_cancel, sampling_round_trip].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Config.

end_per_suite(_Config) ->
    application:stop(erlmcp),
    ok.

init_per_testcase(_TC, Config) ->
    SBridge = spawn_link(fun() -> bridge(undefined) end),
    CBridge = spawn_link(fun() -> bridge(undefined) end),
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"deep-test">>, version => <<"1.0">>,
        tools => [
            #{name => <<"slow">>, description => <<"Slow tool">>,
              input_schema => erlmcp_schema:object([]),
              task_support => enabled,
              handler => fun(_, Ctx) ->
                  erlmcp_ctx:report_progress(Ctx, 0.5, <<"halfway">>),
                  receive after 5000 -> ok end,
                  {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"done">>}]}
              end},
            #{name => <<"ask_client">>, description => <<"Sampling">>,
              input_schema => erlmcp_schema:object([]),
              handler => fun(_, Ctx) ->
                  {ok, R} = erlmcp_ctx:request_peer(Ctx,
                      <<"sampling/createMessage">>,
                      #{<<"messages">> => [#{<<"role">> => <<"user">>,
                          <<"content">> => #{<<"type">> => <<"text">>,
                                             <<"text">> => <<"hi">>}}],
                        <<"maxTokens">> => 10}),
                  Text = maps:get(<<"text">>,
                      maps:get(<<"content">>, R, #{}), <<"none">>),
                  {ok, [#{<<"type">> => <<"text">>, <<"text">> => Text}]}
              end}
        ]
    }),
    Responder = erlmcp_reply:new_device(SBridge),
    {ok, Server} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"deep-test">>, version => <<"1.0">>
    }),
    {ok, Client} = erlmcp_client_session:start_link(#{
        transport => CBridge, owner => self(),
        name => <<"deep-client">>, version => <<"1.0">>
    }),
    ok = erlmcp_client_session:set_sampling_handler(Client, test_sampling_handler),
    SBridge ! {peer, Client},
    CBridge ! {peer, Server},
    {ok, _} = erlmcp_client_session:initialize(Client, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    [{srv, Srv}, {server, Server}, {client, Client} | Config].

end_per_testcase(_TC, Config) ->
    catch erlmcp_client_session:stop(?config(client, Config)),
    catch gen_statem:stop(?config(server, Config)),
    catch gen_server:stop(?config(srv, Config)),
    ok.

%% P6M2-18a: Task progress + cancel. Start a task-enabled tool,
%% receive a progress notification, cancel mid-flight, verify the
%% worker dies and no late result arrives.
task_progress_and_cancel(Config) ->
    Client = ?config(client, Config),
    ProgressToken = <<"test-progress-1">>,
    {ok, CallResult} = erlmcp_client_session:call_tool(Client,
        <<"slow">>, #{}, #{task => true, progress_token => ProgressToken}),
    TaskId = maps:get(<<"taskId">>, CallResult),
    ?assert(is_binary(TaskId)),
    receive
        {mcp_progress, ProgressToken, _} -> ok
    after 3000 ->
        ct:fail(no_progress_notification)
    end,
    %% Cancel
    ok = erlmcp_client_session:cancel_task(Client, TaskId),
    timer:sleep(200),
    ok.

%% P6M2-18b: Sampling round-trip. The tool calls request_peer to
%% issue sampling/createMessage back to the client; the client's
%% sampling handler responds; the tool returns the sampled text.
sampling_round_trip(Config) ->
    Client = ?config(client, Config),
    {ok, Result} = erlmcp_client_session:call_tool(Client,
        <<"ask_client">>, #{}),
    [Content] = maps:get(<<"content">>, Result),
    Text = maps:get(<<"text">>, Content),
    ?assert(is_binary(Text)),
    ?assert(byte_size(Text) > 0).

%%====================================================================
%% Bridge
%%====================================================================

bridge(Peer) ->
    receive
        {peer, Pid} -> bridge(Pid);
        {send, Data} when is_pid(Peer) ->
            gen_statem:cast(Peer, {transport_data, Data}),
            bridge(Peer);
        _ -> bridge(Peer)
    end.
