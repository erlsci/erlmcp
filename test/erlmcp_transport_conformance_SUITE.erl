-module(erlmcp_transport_conformance_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, groups/0, init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).
-export([
    start_stop/1,
    send_data/1,
    validate_config_valid/1,
    validate_config_invalid/1,
    unknown_messages/1,
    session_receives_inbound/1
]).

all() ->
    [{group, stdio}].

groups() ->
    Tests = [start_stop, send_data, validate_config_valid,
             validate_config_invalid, unknown_messages,
             session_receives_inbound],
    [{stdio, [], Tests}].

init_per_group(Group, Config) ->
    [{transport_type, Group} | Config].

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(_TC, Config) ->
    Config.

end_per_testcase(_TC, _Config) ->
    ok.

start_transport(stdio, Session) ->
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => Session
    }),
    ok = erlmcp_transport_stdio:set_session(Pid, Session),
    SendFun = fun(P, Data) -> P ! {send, Data}, ok end,
    {Pid, fun erlmcp_transport_stdio:close/1,
          SendFun,
          fun erlmcp_transport_stdio:simulate_input/2};
start_transport(streamable_http, Session) ->
    {ok, Pid} = erlmcp_transport_streamable_http:start_link(#{
        session => Session, test_mode => true
    }),
    {Pid, fun erlmcp_transport_streamable_http:close/1,
          fun erlmcp_transport_streamable_http:send/2,
          fun erlmcp_transport_streamable_http:simulate_request/2}.

validate_mod(stdio) -> erlmcp_transport_stdio;
validate_mod(streamable_http) -> erlmcp_transport_streamable_http.

%%====================================================================
%% Contract tests
%%====================================================================

start_stop(Config) ->
    Type = ?config(transport_type, Config),
    {Pid, CloseFun, _, _} = start_transport(Type, self()),
    ?assert(is_process_alive(Pid)),
    CloseFun(Pid).

send_data(Config) ->
    Type = ?config(transport_type, Config),
    {Pid, CloseFun, SendFun, _} = start_transport(Type, self()),
    ?assertEqual(ok, SendFun(Pid, <<"test data">>)),
    CloseFun(Pid).

validate_config_valid(Config) ->
    Mod = validate_mod(?config(transport_type, Config)),
    ?assertEqual(ok, Mod:validate_config(#{session => self()})).

validate_config_invalid(Config) ->
    Mod = validate_mod(?config(transport_type, Config)),
    ?assertMatch({error, _}, Mod:validate_config(#{})),
    ?assertMatch({error, _}, Mod:validate_config(not_a_map)).

unknown_messages(Config) ->
    Type = ?config(transport_type, Config),
    {Pid, CloseFun, _, _} = start_transport(Type, self()),
    gen_server:cast(Pid, unknown),
    Pid ! unknown,
    timer:sleep(50),
    ?assert(is_process_alive(Pid)),
    CloseFun(Pid).

session_receives_inbound(Config) ->
    Type = ?config(transport_type, Config),
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    {Pid, CloseFun, _, SimFun} = start_transport(Type, Server),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    ok = SimFun(Pid, InitReq),
    timer:sleep(100),
    ?assertEqual(operational, gen_statem:call(Server, get_state)),
    CloseFun(Pid),
    gen_statem:stop(Server).
