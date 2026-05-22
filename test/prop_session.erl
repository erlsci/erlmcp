-module(prop_session).

-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Property: session state transitions are legal
%%====================================================================

prop_session_lifecycle() ->
    ?FORALL(Commands, list(session_command()),
            begin
                {ok, Server} = erlmcp_server_session:start_link(#{
                    name => <<"prop-server">>,
                    version => <<"1.0">>,
                    capabilities => #{<<"tools">> => #{}},
                    handlers => #{}
                }),
                Result = run_cmds(Server, Commands),
                gen_statem:stop(Server),
                Result
            end).

%%====================================================================
%% Generators
%%====================================================================

session_command() ->
    oneof([
        initialize,
        ping,
        {request, binary()},
        cancel,
        bad_json,
        get_state
    ]).

%%====================================================================
%% Command runner — asserts invariants at each step
%%====================================================================

run_cmds(Server, Commands) ->
    lists:foldl(fun(Cmd, true) -> execute_and_check(Server, Cmd);
                   (_Cmd, false) -> false
                end, true, Commands).

execute_and_check(Server, initialize) ->
    State = gen_statem:call(Server, get_state),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    timer:sleep(10),
    NewState = gen_statem:call(Server, get_state),
    case State of
        uninitialized -> NewState =:= operational;
        _ -> is_process_alive(Server)
    end;

execute_and_check(Server, ping) ->
    State = gen_statem:call(Server, get_state),
    PingReq = erlmcp_json_rpc:encode_request(99, <<"ping">>, #{}),
    erlmcp_server_session:send_message(Server, PingReq),
    timer:sleep(10),
    case State of
        uninitialized ->
            gen_statem:call(Server, get_state) =:= uninitialized;
        operational ->
            is_process_alive(Server)
    end;

execute_and_check(Server, {request, Method}) ->
    Req = erlmcp_json_rpc:encode_request(50, Method, #{}),
    erlmcp_server_session:send_message(Server, Req),
    timer:sleep(10),
    is_process_alive(Server);

execute_and_check(Server, cancel) ->
    CancelNotif = erlmcp_json_rpc:encode_notification(
        <<"notifications/cancelled">>, #{<<"requestId">> => 999}),
    erlmcp_server_session:send_message(Server, CancelNotif),
    timer:sleep(10),
    is_process_alive(Server);

execute_and_check(Server, bad_json) ->
    erlmcp_server_session:send_message(Server, <<"{{garbage">>),
    timer:sleep(10),
    is_process_alive(Server);

execute_and_check(Server, get_state) ->
    State = gen_statem:call(Server, get_state),
    lists:member(State, [uninitialized, initializing, operational, shutting_down]).

%%====================================================================
%% EUnit wrapper
%%====================================================================

session_lifecycle_test() ->
    ?assert(proper:quickcheck(prop_session_lifecycle(),
                              [quiet, {numtests, 50}, {max_size, 10}])).
