-module(erlmcp_stdio_lifecycle_SUITE).

%% P6M2-9: EOF clean shutdown
%% P6M2-14: Dynamic path escape hatch

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0]).
-export([eof_shuts_down_transport/1, dynamic_path_escape_hatch/1]).

all() -> [eof_shuts_down_transport, dynamic_path_escape_hatch].

%% P6M2-9: stdin EOF → reader exits normal → transport stops →
%% subtree (one_for_all, intensity 0) terminates → permanent app dies
%% → node halts. Test: transport process dies after reader EOF.
eof_shuts_down_transport(_Config) ->
    ReadFun = fun() -> eof end,
    {ok, Pid} = erlmcp_transport_stdio:start_link(#{
        session => self(), read_fun => ReadFun
    }),
    unlink(Pid),
    Ref = monitor(process, Pid),
    ok = erlmcp_transport_stdio:serve(Pid),
    receive
        {'DOWN', Ref, process, Pid, normal} -> ok
    after 2000 ->
        ct:fail(transport_did_not_stop_on_eof)
    end.

%% P6M2-14: Dynamic path — start_server + start_transport(paused) +
%% manual register + explicit serve/1.
%% Registering after serve is the unsupported ordering (caller owns gating).
dynamic_path_escape_hatch(_Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"dynamic-test">>, version => <<"1.0">>
    }),
    R = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => R,
        name => <<"dynamic-test">>, version => <<"1.0">>
    }),

    %% Register tools BEFORE serve (the caller owns gating)
    ok = erlmcp_server:register_tool(Srv, #{
        name => <<"dyn_tool">>, description => <<"Dynamic tool">>,
        handler => fun(_, _) ->
            {ok, [#{<<"type">> => <<"text">>, <<"text">> => <<"dynamic">>}]}
        end
    }),

    %% Initialize
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}}),
    erlmcp_server_session:send_message(Session, InitReq),
    InitResp = receive_json(),
    ?assertMatch(#{<<"result">> := #{<<"protocolVersion">> := _}}, InitResp),

    %% Verify tool is visible
    ToolsReq = erlmcp_json_rpc:encode_request(2, <<"tools/list">>, #{}),
    erlmcp_server_session:send_message(Session, ToolsReq),
    ToolsResp = receive_json(),
    Tools = maps:get(<<"tools">>, maps:get(<<"result">>, ToolsResp)),
    Names = [maps:get(<<"name">>, T) || T <- Tools],
    ?assert(lists:member(<<"dyn_tool">>, Names)),

    gen_statem:stop(Session),
    gen_server:stop(Srv).

receive_json() ->
    receive {send, Json} -> {ok, D} = erlmcp_codec:decode(Json), D
    after 2000 -> error(timeout) end.
