-module(erlmcp_m2b_session_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Resources — list, read, templates, subscribe
%%====================================================================

resources_list_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_resource(get(m2b_srv), #{
        uri => <<"test://a">>, name => <<"A">>,
        mime_type => <<"text/plain">>,
        handler => fun(_Ctx) -> {ok, #{<<"uri">> => <<"test://a">>, <<"text">> => <<"hi">>}} end
    }),
    init_session(S),
    Resp = send_req(S, 2, <<"resources/list">>, #{}),
    Resources = maps:get(<<"resources">>, maps:get(<<"result">>, Resp)),
    ?assertEqual(1, length(Resources)),
    [R] = Resources,
    ?assertEqual(<<"test://a">>, maps:get(<<"uri">>, R)),
    ?assertEqual(<<"A">>, maps:get(<<"name">>, R)),
    gen_statem:stop(S).

resources_read_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_resource(get(m2b_srv), #{
        uri => <<"test://a">>, name => <<"A">>,
        handler => fun(_Ctx) -> {ok, #{<<"uri">> => <<"test://a">>, <<"text">> => <<"content">>}} end
    }),
    init_session(S),
    Resp = send_req(S, 2, <<"resources/read">>, #{<<"uri">> => <<"test://a">>}),
    Result = maps:get(<<"result">>, Resp),
    [C] = maps:get(<<"contents">>, Result),
    ?assertEqual(<<"content">>, maps:get(<<"text">>, C)),
    gen_statem:stop(S).

resources_read_not_found_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    Resp = send_req(S, 2, <<"resources/read">>, #{<<"uri">> => <<"nonexistent">>}),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32002}}, Resp),
    gen_statem:stop(S).

resources_read_missing_uri_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    Resp = send_req(S, 2, <<"resources/read">>, #{}),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp),
    gen_statem:stop(S).

resources_read_template_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_resource_template(get(m2b_srv), #{
        uri_template => <<"test://{id}">>, name => <<"Item">>,
        handler => fun(#{<<"id">> := Id}, _Ctx) ->
            {ok, #{<<"uri">> => <<"test://", Id/binary>>, <<"text">> => Id}}
        end
    }),
    init_session(S),
    Resp = send_req(S, 2, <<"resources/read">>, #{<<"uri">> => <<"test://42">>}),
    Result = maps:get(<<"result">>, Resp),
    [C] = maps:get(<<"contents">>, Result),
    ?assertEqual(<<"42">>, maps:get(<<"text">>, C)),
    gen_statem:stop(S).

resource_templates_list_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_resource_template(get(m2b_srv), #{
        uri_template => <<"test://{id}">>, name => <<"Item">>,
        handler => fun(_, _) -> {ok, #{<<"uri">> => <<"x">>, <<"text">> => <<"y">>}} end
    }),
    init_session(S),
    Resp = send_req(S, 2, <<"resources/templates/list">>, #{}),
    Tpls = maps:get(<<"resourceTemplates">>, maps:get(<<"result">>, Resp)),
    ?assertEqual(1, length(Tpls)),
    gen_statem:stop(S).

resources_subscribe_updated_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_resource(get(m2b_srv), #{
        uri => <<"test://a">>, name => <<"A">>,
        handler => fun(_Ctx) -> {ok, #{<<"uri">> => <<"test://a">>, <<"text">> => <<"x">>}} end
    }),
    init_session(S),
    _ = send_req(S, 3, <<"resources/subscribe">>, #{<<"uri">> => <<"test://a">>}),
    gen_statem:cast(S, {resource_updated, <<"test://a">>}),
    Notif = decode(wait_send()),
    ?assertEqual(<<"notifications/resources/updated">>, maps:get(<<"method">>, Notif)),
    gen_statem:stop(S).

resources_unsubscribe_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    _ = send_req(S, 3, <<"resources/subscribe">>, #{<<"uri">> => <<"test://a">>}),
    _ = send_req(S, 4, <<"resources/unsubscribe">>, #{<<"uri">> => <<"test://a">>}),
    gen_statem:cast(S, {resource_updated, <<"test://a">>}),
    receive {send, _} -> ?assert(false) after 200 -> ok end,
    gen_statem:stop(S).

resources_list_changed_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    ok = erlmcp_server:register_resource(get(m2b_srv), #{
        uri => <<"test://b">>, name => <<"B">>,
        handler => fun(_Ctx) -> {ok, #{<<"uri">> => <<"test://b">>, <<"text">> => <<"y">>}} end
    }),
    Notif = decode(wait_send()),
    ?assertEqual(<<"notifications/resources/list_changed">>, maps:get(<<"method">>, Notif)),
    ok = erlmcp_server:unregister_resource(get(m2b_srv), <<"test://b">>),
    Notif2 = decode(wait_send()),
    ?assertEqual(<<"notifications/resources/list_changed">>, maps:get(<<"method">>, Notif2)),
    gen_statem:stop(S).

%%====================================================================
%% Prompts — list, get, list_changed
%%====================================================================

prompts_list_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_prompt(get(m2b_srv), #{
        name => <<"greet">>, description => <<"Greet">>,
        arguments => [#{name => <<"name">>, required => true}],
        handler => fun(#{<<"name">> := N}, _) ->
            {ok, [#{<<"role">> => <<"user">>,
                    <<"content">> => #{<<"type">> => <<"text">>,
                                       <<"text">> => <<"Hello ", N/binary>>}}]}
        end
    }),
    init_session(S),
    Resp = send_req(S, 2, <<"prompts/list">>, #{}),
    [P] = maps:get(<<"prompts">>, maps:get(<<"result">>, Resp)),
    ?assertEqual(<<"greet">>, maps:get(<<"name">>, P)),
    [Arg] = maps:get(<<"arguments">>, P),
    ?assertEqual(true, maps:get(<<"required">>, Arg)),
    gen_statem:stop(S).

prompts_get_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_prompt(get(m2b_srv), #{
        name => <<"greet">>, description => <<"Greet">>,
        handler => fun(#{<<"name">> := N}, _) ->
            {ok, [#{<<"role">> => <<"user">>,
                    <<"content">> => #{<<"type">> => <<"text">>,
                                       <<"text">> => <<"Hi ", N/binary>>}}]}
        end
    }),
    init_session(S),
    Resp = send_req(S, 2, <<"prompts/get">>,
                    #{<<"name">> => <<"greet">>,
                      <<"arguments">> => #{<<"name">> => <<"world">>}}),
    Result = maps:get(<<"result">>, Resp),
    [Msg] = maps:get(<<"messages">>, Result),
    Text = maps:get(<<"text">>, maps:get(<<"content">>, Msg)),
    ?assertEqual(<<"Hi world">>, Text),
    gen_statem:stop(S).

prompts_get_not_found_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    Resp = send_req(S, 2, <<"prompts/get">>,
                    #{<<"name">> => <<"nonexistent">>}),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32003}}, Resp),
    gen_statem:stop(S).

prompts_get_missing_name_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    Resp = send_req(S, 2, <<"prompts/get">>, #{}),
    ?assertMatch(#{<<"error">> := #{<<"code">> := -32602}}, Resp),
    gen_statem:stop(S).

prompts_list_changed_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    ok = erlmcp_server:register_prompt(get(m2b_srv), #{
        name => <<"tmp">>, description => <<"Tmp">>,
        handler => fun(_, _) -> {ok, []} end
    }),
    Notif = decode(wait_send()),
    ?assertEqual(<<"notifications/prompts/list_changed">>, maps:get(<<"method">>, Notif)),
    ok = erlmcp_server:unregister_prompt(get(m2b_srv), <<"tmp">>),
    Notif2 = decode(wait_send()),
    ?assertEqual(<<"notifications/prompts/list_changed">>, maps:get(<<"method">>, Notif2)),
    gen_statem:stop(S).

%%====================================================================
%% Logging — setLevel + filter
%%====================================================================

logging_set_level_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    Resp = send_req(S, 2, <<"logging/setLevel">>, #{<<"level">> => <<"warning">>}),
    ?assertMatch(#{<<"result">> := #{}}, Resp),
    gen_statem:stop(S).

logging_filter_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    _ = send_req(S, 2, <<"logging/setLevel">>, #{<<"level">> => <<"error">>}),
    erlmcp_server_session:emit_log(S, debug, <<"t">>, <<"no">>),
    receive {send, _} -> ?assert(false) after 200 -> ok end,
    erlmcp_server_session:emit_log(S, error, <<"t">>, <<"yes">>),
    Notif = decode(wait_send()),
    ?assertEqual(<<"notifications/message">>, maps:get(<<"method">>, Notif)),
    ?assertEqual(<<"error">>, maps:get(<<"level">>, maps:get(<<"params">>, Notif))),
    gen_statem:stop(S).

logging_invalid_level_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    init_session(S),
    Resp = send_req(S, 2, <<"logging/setLevel">>, #{<<"level">> => <<"bogus">>}),
    ?assertMatch(#{<<"error">> := _}, Resp),
    gen_statem:stop(S).

%%====================================================================
%% Completion
%%====================================================================

completion_prompt_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_prompt(get(m2b_srv), #{
        name => <<"p">>, description => <<"P">>,
        handler => fun(_, _) -> {ok, []} end,
        completions => #{<<"arg">> => fun(_Prefix) -> [<<"val1">>, <<"val2">>] end}
    }),
    init_session(S),
    Resp = send_req(S, 2, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/prompt">>, <<"name">> => <<"p">>},
        <<"argument">> => #{<<"name">> => <<"arg">>, <<"value">> => <<"">>}
    }),
    Completion = maps:get(<<"completion">>, maps:get(<<"result">>, Resp)),
    ?assertEqual([<<"val1">>, <<"val2">>], maps:get(<<"values">>, Completion)),
    gen_statem:stop(S).

completion_template_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_resource_template(get(m2b_srv), #{
        uri_template => <<"t://{x}">>, name => <<"T">>,
        handler => fun(_, _) -> {ok, #{<<"uri">> => <<"t://1">>, <<"text">> => <<"ok">>}} end,
        completions => #{<<"x">> => fun(_) -> [<<"a">>, <<"b">>] end}
    }),
    init_session(S),
    Resp = send_req(S, 2, <<"completion/complete">>, #{
        <<"ref">> => #{<<"type">> => <<"ref/resource">>, <<"uri">> => <<"t://{x}">>},
        <<"argument">> => #{<<"name">> => <<"x">>, <<"value">> => <<"">>}
    }),
    Vals = maps:get(<<"values">>, maps:get(<<"completion">>, maps:get(<<"result">>, Resp))),
    ?assertEqual([<<"a">>, <<"b">>], Vals),
    gen_statem:stop(S).

%%====================================================================
%% Capability map
%%====================================================================

capability_resources_prompts_test() ->
    Transport = self(),
    {ok, S} = start_server(Transport),
    ok = erlmcp_server:register_resource(get(m2b_srv), #{
        uri => <<"x://a">>, name => <<"A">>,
        handler => fun(_) -> {ok, #{<<"uri">> => <<"x://a">>, <<"text">> => <<"t">>}} end
    }),
    ok = erlmcp_server:register_prompt(get(m2b_srv), #{
        name => <<"p">>, description => <<"P">>,
        handler => fun(_, _) -> {ok, []} end
    }),
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(S, InitReq),
    Resp = decode(wait_send()),
    Caps = maps:get(<<"capabilities">>, maps:get(<<"result">>, Resp)),
    ?assert(maps:is_key(<<"resources">>, Caps)),
    ?assert(maps:is_key(<<"prompts">>, Caps)),
    ?assert(maps:is_key(<<"logging">>, Caps)),
    gen_statem:stop(S).

%%====================================================================
%% Helpers
%%====================================================================

start_server(_Transport) ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    put(m2b_srv, Srv),
    {ok, Session}.

init_session(S) ->
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>, <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(S, InitReq),
    _ = wait_send(),
    ok.

send_req(S, Id, Method, Params) ->
    Req = erlmcp_json_rpc:encode_request(Id, Method, Params),
    erlmcp_server_session:send_message(S, Req),
    decode(wait_send()).

decode(Json) ->
    {ok, D} = erlmcp_codec:decode(Json), D.

wait_send() ->
    receive {send, Data} -> Data after 5000 -> error(transport_send_timeout) end.
