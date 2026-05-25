-module(erlmcp_example_weather_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
    resources_list/1,
    resources_read_static/1,
    resources_read_template/1,
    resource_templates_list/1,
    resources_subscribe_updated/1,
    resources_unsubscribe_silence/1,
    resources_list_changed/1,
    prompts_list/1,
    prompts_get_with_args/1,
    prompts_list_changed/1,
    logging_set_level_and_filter/1,
    completion_prompt_arg/1,
    completion_template_param/1,
    capability_map_resources_prompts/1,
    pagination_resources/1
]).

all() ->
    [resources_list,
     resources_read_static,
     resources_read_template,
     resource_templates_list,
     resources_subscribe_updated,
     resources_unsubscribe_silence,
     resources_list_changed,
     prompts_list,
     prompts_get_with_args,
     prompts_list_changed,
     logging_set_level_and_filter,
     completion_prompt_arg,
     completion_template_param,
     capability_map_resources_prompts,
     pagination_resources].

init_per_testcase(_TC, Config) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"weather-server">>, version => <<"1.0">>
    }),
    ok = example_weather_handler:register_all(Srv),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"weather-server">>, version => <<"1.0">>
    }),
    initialize(Session),
    [{server, Session}, {srv, Srv} | Config].

end_per_testcase(_TC, Config) ->
    Session = ?config(server, Config),
    Srv = ?config(srv, Config),
    catch gen_statem:stop(Session),
    catch gen_server:stop(Srv),
    ok.

%%====================================================================
%% Helpers
%%====================================================================

initialize(Server) ->
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _ = wait_send(),
    ok.

wait_send() ->
    receive {send, Data} -> Data after 5000 -> error(transport_send_timeout) end.

decode(Json) ->
    {ok, Decoded} = erlmcp_codec:decode(Json),
    Decoded.

send_request(Server, Id, Method, Params) ->
    Req = erlmcp_json_rpc:encode_request(Id, Method, Params),
    erlmcp_server_session:send_message(Server, Req),
    decode(wait_send()).

%%====================================================================
%% M2b-1: resources/list + resources/read
%%====================================================================

resources_list(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"resources/list">>, #{}),
    Resources = maps:get(<<"resources">>, maps:get(<<"result">>, Resp)),
    ?assert(length(Resources) >= 1),
    London = hd([R || R <- Resources,
                      maps:get(<<"uri">>, R) =:= <<"weather://current/london">>]),
    ?assertEqual(<<"London Weather">>, maps:get(<<"name">>, London)).

resources_read_static(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"resources/read">>,
                        #{<<"uri">> => <<"weather://current/london">>}),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"contents">>, Result),
    ?assertEqual(<<"weather://current/london">>, maps:get(<<"uri">>, Content)),
    ?assert(is_binary(maps:get(<<"text">>, Content))).

%%====================================================================
%% M2b-2: resource templates
%%====================================================================

resources_read_template(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"resources/read">>,
                        #{<<"uri">> => <<"weather://current/paris">>}),
    Result = maps:get(<<"result">>, Resp),
    [Content] = maps:get(<<"contents">>, Result),
    Text = maps:get(<<"text">>, Content),
    {ok, Parsed} = erlmcp_codec:decode(Text),
    ?assertEqual(<<"paris">>, maps:get(<<"city">>, Parsed)).

resource_templates_list(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"resources/templates/list">>, #{}),
    Templates = maps:get(<<"resourceTemplates">>, maps:get(<<"result">>, Resp)),
    ?assert(length(Templates) >= 1),
    [Tpl] = Templates,
    ?assertEqual(<<"weather://current/{city}">>, maps:get(<<"uriTemplate">>, Tpl)).

%%====================================================================
%% M2b-3: subscribe/unsubscribe + notifications/resources/updated
%%====================================================================

resources_subscribe_updated(Config) ->
    Server = ?config(server, Config),
    _SubResp = send_request(Server, 3, <<"resources/subscribe">>,
                            #{<<"uri">> => <<"weather://current/london">>}),
    erlmcp:notify_resource_updated(Server, <<"weather://current/london">>),
    Notif = decode(wait_send()),
    ?assertEqual(<<"notifications/resources/updated">>,
                 maps:get(<<"method">>, Notif)),
    ?assertEqual(<<"weather://current/london">>,
                 maps:get(<<"uri">>, maps:get(<<"params">>, Notif))).

resources_unsubscribe_silence(Config) ->
    Server = ?config(server, Config),
    _SubResp = send_request(Server, 3, <<"resources/subscribe">>,
                            #{<<"uri">> => <<"weather://current/london">>}),
    _UnsubResp = send_request(Server, 4, <<"resources/unsubscribe">>,
                              #{<<"uri">> => <<"weather://current/london">>}),
    erlmcp:notify_resource_updated(Server, <<"weather://current/london">>),
    receive {send, _} -> ct:fail(should_not_receive_notification)
    after 200 -> ok
    end.

%%====================================================================
%% M2b-4: notifications/resources/list_changed
%%====================================================================

resources_list_changed(Config) ->
    Srv = ?config(srv, Config),
    ok = erlmcp:add_resource(Srv, #{
        uri => <<"weather://forecast/london">>,
        name => <<"London Forecast">>,
        handler => fun(_Ctx) -> {ok, #{<<"uri">> => <<"weather://forecast/london">>,
                                       <<"text">> => <<"sunny">>}} end
    }),
    Notif1 = decode(wait_send()),
    ?assertEqual(<<"notifications/resources/list_changed">>,
                 maps:get(<<"method">>, Notif1)),
    ok = erlmcp:remove_resource(Srv, <<"weather://forecast/london">>),
    Notif2 = decode(wait_send()),
    ?assertEqual(<<"notifications/resources/list_changed">>,
                 maps:get(<<"method">>, Notif2)).

%%====================================================================
%% M2b-5: prompts/list + prompts/get
%%====================================================================

prompts_list(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"prompts/list">>, #{}),
    Prompts = maps:get(<<"prompts">>, maps:get(<<"result">>, Resp)),
    ?assertEqual(1, length(Prompts)),
    [P] = Prompts,
    ?assertEqual(<<"weather_report">>, maps:get(<<"name">>, P)),
    Args = maps:get(<<"arguments">>, P),
    ?assertEqual(2, length(Args)),
    CityArg = hd([A || A <- Args, maps:get(<<"name">>, A) =:= <<"city">>]),
    ?assertEqual(true, maps:get(<<"required">>, CityArg)).

prompts_get_with_args(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"prompts/get">>,
                        #{<<"name">> => <<"weather_report">>,
                          <<"arguments">> => #{<<"city">> => <<"london">>,
                                               <<"units">> => <<"f">>}}),
    Result = maps:get(<<"result">>, Resp),
    Messages = maps:get(<<"messages">>, Result),
    ?assertEqual(1, length(Messages)),
    [Msg] = Messages,
    ?assertEqual(<<"user">>, maps:get(<<"role">>, Msg)),
    Text = maps:get(<<"text">>, maps:get(<<"content">>, Msg)),
    ?assert(binary:match(Text, <<"london">>) =/= nomatch),
    ?assert(binary:match(Text, <<"f">>) =/= nomatch).

%%====================================================================
%% M2b-6: notifications/prompts/list_changed
%%====================================================================

prompts_list_changed(Config) ->
    Srv = ?config(srv, Config),
    ok = erlmcp:add_prompt(Srv, #{
        name => <<"temp_prompt">>,
        description => <<"Temporary">>,
        handler => fun(_, _) -> {ok, []} end
    }),
    Notif1 = decode(wait_send()),
    ?assertEqual(<<"notifications/prompts/list_changed">>,
                 maps:get(<<"method">>, Notif1)),
    ok = erlmcp:remove_prompt(Srv, <<"temp_prompt">>),
    Notif2 = decode(wait_send()),
    ?assertEqual(<<"notifications/prompts/list_changed">>,
                 maps:get(<<"method">>, Notif2)).

%%====================================================================
%% M2b-7: logging/setLevel + notifications/message
%%====================================================================

logging_set_level_and_filter(Config) ->
    Server = ?config(server, Config),
    _SetResp = send_request(Server, 2, <<"logging/setLevel">>,
                            #{<<"level">> => <<"warning">>}),
    erlmcp:log_message(Server, debug, <<"test">>, <<"should be suppressed">>),
    receive {send, _} -> ct:fail(debug_should_be_suppressed)
    after 200 -> ok
    end,
    erlmcp:log_message(Server, error, <<"test">>, <<"should be emitted">>),
    Notif = decode(wait_send()),
    ?assertEqual(<<"notifications/message">>, maps:get(<<"method">>, Notif)),
    Params = maps:get(<<"params">>, Notif),
    ?assertEqual(<<"error">>, maps:get(<<"level">>, Params)),
    ?assertEqual(<<"should be emitted">>, maps:get(<<"data">>, Params)).

%%====================================================================
%% M2b-8: completion/complete
%%====================================================================

completion_prompt_arg(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"weather_report">>},
        <<"argument">> => #{<<"name">> => <<"city">>, <<"value">> => <<"lon">>}
    }),
    Completion = maps:get(<<"completion">>, maps:get(<<"result">>, Resp)),
    Values = maps:get(<<"values">>, Completion),
    ?assert(lists:member(<<"london">>, Values)).

completion_template_param(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/resource">>,
                       <<"uri">> => <<"weather://current/{city}">>},
        <<"argument">> => #{<<"name">> => <<"city">>, <<"value">> => <<"par">>}
    }),
    Completion = maps:get(<<"completion">>, maps:get(<<"result">>, Resp)),
    Values = maps:get(<<"values">>, Completion),
    ?assert(lists:member(<<"paris">>, Values)).

%%====================================================================
%% M2b-10: capability map includes resources/prompts/logging
%%====================================================================

capability_map_resources_prompts(Config) ->
    Server = ?config(server, Config),
    Srv = ?config(srv, Config),
    gen_statem:stop(Server),
    gen_server:stop(Srv),
    {ok, Srv2} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>
    }),
    ok = example_weather_handler:register_all(Srv2),
    Responder2 = erlmcp_reply:new_device(self()),
    {ok, Session2} = erlmcp_server_session:start_link(#{
        server => Srv2, responder => Responder2,
        name => <<"test">>, version => <<"1.0">>
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Session2, InitReq),
    Resp = decode(wait_send()),
    Caps = maps:get(<<"capabilities">>, maps:get(<<"result">>, Resp)),
    ?assert(maps:is_key(<<"resources">>, Caps)),
    ResCap = maps:get(<<"resources">>, Caps),
    ?assertEqual(true, maps:get(<<"subscribe">>, ResCap)),
    ?assertEqual(true, maps:get(<<"listChanged">>, ResCap)),
    ?assert(maps:is_key(<<"prompts">>, Caps)),
    ?assertEqual(true, maps:get(<<"listChanged">>, maps:get(<<"prompts">>, Caps))),
    ?assert(maps:is_key(<<"logging">>, Caps)),
    gen_statem:stop(Session2),
    gen_server:stop(Srv2).

%%====================================================================
%% M2b-9: pagination consistency across endpoints
%%====================================================================

pagination_resources(Config) ->
    Server = ?config(server, Config),
    Resp = send_request(Server, 2, <<"resources/list">>, #{}),
    Result = maps:get(<<"result">>, Resp),
    ?assert(is_list(maps:get(<<"resources">>, Result))),
    ?assertNot(maps:is_key(<<"nextCursor">>, Result)).
