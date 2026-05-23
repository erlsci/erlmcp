-module(erlmcp_supervision_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
    app_starts_sups/1,
    sup_children/1,
    session_sup_standalone/1,
    server_sup_standalone/1,
    transport_sup_standalone/1,
    sup_start_stop_server/1,
    sup_start_stop_transport/1,
    sup_start_stop_transport_full/1,
    transport_sup_tcp_type/1,
    transport_sup_http_type/1
]).

all() ->
    [app_starts_sups, sup_children,
     session_sup_standalone, server_sup_standalone, transport_sup_standalone,
     sup_start_stop_server, sup_start_stop_transport,
     sup_start_stop_transport_full,
     transport_sup_tcp_type, transport_sup_http_type,
     transport_sup_start_child,
     sup_start_server_via_facade].

init_per_testcase(_TC, Config) ->
    Config.

end_per_testcase(_TC, _Config) ->
    catch application:stop(erlmcp),
    timer:sleep(100),
    ok.

app_starts_sups(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ?assert(is_pid(whereis(erlmcp_sup))),
    ?assert(is_pid(whereis(erlmcp_registry))),
    _ = Config.

sup_children(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    Children = supervisor:which_children(erlmcp_sup),
    Ids = [Id || {Id, _, _, _} <- Children],
    ?assert(lists:member(erlmcp_registry, Ids)),
    ?assert(lists:member(erlmcp_server_sup, Ids)),
    ?assert(lists:member(erlmcp_transport_sup, Ids)),
    _ = Config.

session_sup_standalone(Config) ->
    {ok, Pid} = erlmcp_session_sup:start_link(),
    ?assert(is_process_alive(Pid)),
    unlink(Pid),
    exit(Pid, shutdown),
    timer:sleep(50),
    _ = Config.

server_sup_standalone(Config) ->
    {ok, Pid} = erlmcp_server_sup:start_link(),
    ?assert(is_process_alive(Pid)),
    Children = supervisor:which_children(Pid),
    ?assertEqual([], Children),
    unlink(Pid),
    exit(Pid, shutdown),
    timer:sleep(50),
    _ = Config.

transport_sup_standalone(Config) ->
    {ok, Pid} = erlmcp_transport_sup:start_link(),
    ?assert(is_process_alive(Pid)),
    unlink(Pid),
    exit(Pid, shutdown),
    timer:sleep(50),
    _ = Config.

sup_start_stop_server(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ok = erlmcp_sup:stop_server(nonexistent),
    ?assertEqual({error, removed}, erlmcp_sup:start_stdio_server()),
    ?assertEqual({error, removed}, erlmcp_sup:start_stdio_server(#{})),
    ok = erlmcp_sup:stop_stdio_server(),
    _ = Config.

sup_start_stop_transport(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    ok = erlmcp_sup:stop_transport(nonexistent),
    _ = Config.

%%====================================================================
%% Transport sup start_child
%%====================================================================

transport_sup_start_child(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, Pid} = erlmcp_transport_sup:start_child(
        test_stdio_transport, stdio, #{session => self(), test_mode => true}),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid),
    _ = Config.

%%====================================================================
%% Sup start_server + start_transport via facade
%%====================================================================

sup_start_server_via_facade(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, ServerPid} = erlmcp_sup:start_server(test_facade_srv,
        #{name => <<"test">>, version => <<"1.0">>}),
    ?assert(is_process_alive(ServerPid)),
    ok = erlmcp_sup:stop_server(test_facade_srv),
    timer:sleep(100),
    _ = Config.

sup_start_transport_via_facade(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, TransPid} = erlmcp_sup:start_transport(test_facade_trans, stdio,
        #{session => self(), test_mode => true}),
    ?assert(is_process_alive(TransPid)),
    ok = erlmcp_sup:stop_transport(test_facade_trans),
    timer:sleep(100),
    _ = Config.

sup_start_stop_transport_full(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, _TransPid} = erlmcp_sup:start_transport(full_t, stdio,
        #{session => self(), test_mode => true}),
    ok = erlmcp_sup:stop_transport(full_t),
    ?assertEqual(ok, erlmcp_sup:stop_transport(nonexistent_t)),
    _ = Config.

transport_sup_tcp_type(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, _TcpPid} = erlmcp_sup:start_transport(tcp_t, tcp,
        #{host => "localhost", port => 1, owner => self(),
          max_reconnect_attempts => 0}),
    ok = erlmcp_sup:stop_transport(tcp_t),
    _ = Config.

transport_sup_http_type(Config) ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, _HttpPid} = erlmcp_sup:start_transport(http_t, http,
        #{url => "http://localhost:1/mcp", owner => self()}),
    ok = erlmcp_sup:stop_transport(http_t),
    _ = Config.
