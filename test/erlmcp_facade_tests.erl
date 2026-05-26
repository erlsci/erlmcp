-module(erlmcp_facade_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Tool API
%%====================================================================

add_tool_test() ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    Schema = erlmcp_schema:object([
        erlmcp_schema:field(<<"x">>, erlmcp_schema:number(), [required])
    ]),
    ok = erlmcp:add_tool(Server, #{
        name => <<"t">>, description => <<"t">>,
        input_schema => Schema,
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    [Tool] = maps:values(erlmcp_server:get_tools(erlmcp_server:catalog_table(Server))),
    ?assertEqual(<<"t">>, maps:get(name, Tool)),
    gen_server:stop(Server).

remove_tool_test() ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp:add_tool(Server, #{
        name => <<"t">>, description => <<"t">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    ok = erlmcp:remove_tool(Server, <<"t">>),
    ?assertEqual([], maps:values(erlmcp_server:get_tools(erlmcp_server:catalog_table(Server)))),
    gen_server:stop(Server).

register_handler_test() ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp:register_handler(Server, test_calc_handler),
    Tools = maps:values(erlmcp_server:get_tools(erlmcp_server:catalog_table(Server))),
    ?assert(length(Tools) > 0),
    gen_server:stop(Server).

%%====================================================================
%% Content constructors
%%====================================================================

text_test() ->
    C = erlmcp:text(<<"hello">>),
    ?assertEqual(<<"text">>, maps:get(<<"type">>, C)),
    ?assertEqual(<<"hello">>, maps:get(<<"text">>, C)).

image_test() ->
    C = erlmcp:image(<<"data">>, <<"image/png">>),
    ?assertEqual(<<"image">>, maps:get(<<"type">>, C)),
    ?assertEqual(<<"data">>, maps:get(<<"data">>, C)),
    ?assertEqual(<<"image/png">>, maps:get(<<"mimeType">>, C)).

audio_test() ->
    C = erlmcp:audio(<<"data">>, <<"audio/wav">>),
    ?assertEqual(<<"audio">>, maps:get(<<"type">>, C)),
    ?assertEqual(<<"audio/wav">>, maps:get(<<"mimeType">>, C)).

embedded_resource_test() ->
    R = #{<<"uri">> => <<"file:///a">>},
    C = erlmcp:embedded_resource(R),
    ?assertEqual(<<"resource">>, maps:get(<<"type">>, C)),
    ?assertEqual(R, maps:get(<<"resource">>, C)).

resource_link_test() ->
    C = erlmcp:resource_link(<<"file:///b">>, <<"text/plain">>),
    ?assertEqual(<<"resource_link">>, maps:get(<<"type">>, C)),
    ?assertEqual(<<"file:///b">>, maps:get(<<"uri">>, C)).

%%====================================================================
%% Discoverability
%%====================================================================

make_directory_tool_test() ->
    T = erlmcp:make_directory_tool(),
    ?assertEqual(<<"directory">>, maps:get(name, T)),
    ?assert(maps:get(is_directory, T)).

conformance_tools_excludes_directory_test() ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp:add_tool(Server, erlmcp:make_directory_tool()),
    ok = erlmcp:add_tool(Server, #{
        name => <<"t">>, description => <<"t">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    CTools = erlmcp:conformance_tools(Server),
    Names = [maps:get(name, T) || T <- CTools],
    ?assert(lists:member(<<"t">>, Names)),
    ?assertNot(lists:member(<<"directory">>, Names)),
    gen_server:stop(Server).

%%====================================================================
%% Server management (existing functional code)
%%====================================================================

start_stop_server_test() ->
    {ok, Pid} = erlmcp:start_server(test_srv),
    ?assert(is_process_alive(Pid)),
    gen_server:stop(Pid).

start_server_with_config_test() ->
    {ok, Pid} = erlmcp:start_server(test_srv2, #{version => <<"2.0">>}),
    ?assert(is_process_alive(Pid)),
    gen_server:stop(Pid).

list_servers_no_registry_test() ->
    ?assertEqual([], erlmcp:list_servers()).

stop_server_no_registry_test() ->
    ?assertEqual({error, registry_not_available}, erlmcp:stop_server(nonexistent)).

list_transports_no_registry_test() ->
    ?assertEqual([], erlmcp:list_transports()).

stop_transport_no_registry_test() ->
    ?assertEqual({error, registry_not_available}, erlmcp:stop_transport(nonexistent)).

bind_transport_no_registry_test() ->
    ?assertEqual({error, registry_not_available},
                 erlmcp:bind_transport_to_server(t, s)).

unbind_transport_no_registry_test() ->
    ?assertEqual({error, registry_not_available},
                 erlmcp:unbind_transport(t)).

start_transport_unsupported_test() ->
    ?assertEqual({error, {transport_not_implemented, tcp}},
                 erlmcp:start_transport(t, tcp)).

%%====================================================================
%% Resources (M2b)
%%====================================================================

add_resource_test() ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp:add_resource(Server, #{
        uri => <<"test://a">>,
        name => <<"Test A">>,
        handler => fun(_Ctx) -> {ok, #{<<"uri">> => <<"test://a">>, <<"text">> => <<"hello">>}} end
    }),
    [R] = maps:values(erlmcp_server:get_resources(erlmcp_server:catalog_table(Server))),
    ?assertEqual(<<"test://a">>, maps:get(uri, R)),
    ok = erlmcp:remove_resource(Server, <<"test://a">>),
    ?assertEqual([], maps:values(erlmcp_server:get_resources(erlmcp_server:catalog_table(Server)))),
    gen_server:stop(Server).

add_resource_template_test() ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp:add_resource_template(Server, #{
        uri_template => <<"test://{id}">>,
        name => <<"Test">>,
        handler => fun(_Params, _Ctx) -> {ok, #{<<"uri">> => <<"test://1">>, <<"text">> => <<"ok">>}} end
    }),
    [T] = maps:values(erlmcp_server:get_resource_templates(erlmcp_server:catalog_table(Server))),
    ?assertEqual(<<"test://{id}">>, maps:get(uri_template, T)),
    ok = erlmcp:remove_resource_template(Server, <<"test://{id}">>),
    ?assertEqual([], maps:values(erlmcp_server:get_resource_templates(erlmcp_server:catalog_table(Server)))),
    gen_server:stop(Server).

%%====================================================================
%% Prompts (M2b)
%%====================================================================

add_prompt_test() ->
    {ok, Server} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp:add_prompt(Server, #{
        name => <<"greet">>,
        description => <<"Greeting prompt">>,
        arguments => [#{name => <<"name">>, required => true}],
        handler => fun(#{<<"name">> := N}, _Ctx) ->
            {ok, [#{<<"role">> => <<"user">>, <<"content">> =>
                #{<<"type">> => <<"text">>, <<"text">> => <<"Hello ", N/binary>>}}]}
        end
    }),
    [P] = maps:values(erlmcp_server:get_prompts(erlmcp_server:catalog_table(Server))),
    ?assertEqual(<<"greet">>, maps:get(name, P)),
    ok = erlmcp:remove_prompt(Server, <<"greet">>),
    ?assertEqual([], maps:values(erlmcp_server:get_prompts(erlmcp_server:catalog_table(Server)))),
    gen_server:stop(Server).

%%====================================================================
%% Logging (M2b)
%%====================================================================

log_message_test() ->
    {ok, Srv} = erlmcp_server:start_link(#{
        name => <<"test">>, version => <<"1.0">>
    }),
    Responder = erlmcp_reply:new_device(self()),
    {ok, Session} = erlmcp_server_session:start_link(#{
        server => Srv, responder => Responder,
        name => <<"test">>, version => <<"1.0">>
    }),
    init_server_with_transport(Session),
    ok = erlmcp_server_session:set_log_level(Session, info),
    erlmcp:log_message(Session, info, <<"test">>, <<"hello">>),
    Notif = decode_resp(wait_transport_send()),
    ?assertEqual(<<"notifications/message">>, maps:get(<<"method">>, Notif)),
    Params = maps:get(<<"params">>, Notif),
    ?assertEqual(<<"info">>, maps:get(<<"level">>, Params)),
    gen_statem:stop(Session),
    gen_server:stop(Srv).

%%====================================================================
%% Facade transport/server management (via app)
%%====================================================================

stop_server_running_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, Pid} = erlmcp:start_server(test_stop_srv),
    ok = erlmcp_registry:register_server(test_stop_srv, Pid, #{}),
    ?assert(is_process_alive(Pid)),
    ok = erlmcp:stop_server(test_stop_srv),
    ok = application:stop(erlmcp),
    timer:sleep(100).

bind_unbind_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, ServerPid} = erlmcp:start_server(bind_test_srv),
    ok = erlmcp_registry:register_server(bind_test_srv, ServerPid, #{}),
    {ok, TransPid} = erlmcp:start_transport(bind_test_t, stdio,
        #{session => self(), test_mode => true}),
    ok = erlmcp_registry:register_transport(bind_test_t, TransPid, #{}),
    ok = erlmcp:bind_transport_to_server(bind_test_t, bind_test_srv),
    ok = erlmcp:unbind_transport(bind_test_t),
    erlmcp_transport_stdio:close(TransPid),
    ok = erlmcp:stop_server(bind_test_srv),
    ok = application:stop(erlmcp),
    timer:sleep(100).

list_servers_running_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, Pid} = erlmcp:start_server(ls_test_srv),
    ok = erlmcp_registry:register_server(ls_test_srv, Pid, #{}),
    Servers = erlmcp:list_servers(),
    ?assert(length(Servers) >= 1),
    erlmcp:stop_server(ls_test_srv),
    ok = application:stop(erlmcp),
    timer:sleep(100).

list_transports_running_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, TransPid} = erlmcp:start_transport(lt_test, stdio,
        #{session => self(), test_mode => true}),
    ok = erlmcp_registry:register_transport(lt_test, TransPid, #{}),
    Transports = erlmcp:list_transports(),
    ?assert(length(Transports) >= 1),
    ok = application:stop(erlmcp),
    timer:sleep(100).

stop_transport_running_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, TransPid} = erlmcp:start_transport(st_test, stdio,
        #{session => self(), test_mode => true}),
    ok = erlmcp_registry:register_transport(st_test, TransPid, #{}),
    ok = erlmcp:stop_transport(st_test),
    ok = application:stop(erlmcp),
    timer:sleep(100).

start_stop_transport_stdio_test() ->
    {ok, Pid} = erlmcp:start_transport(test_t, stdio, #{
        session => self(), test_mode => true
    }),
    ?assert(is_process_alive(Pid)),
    erlmcp_transport_stdio:close(Pid).

notify_resource_updated_test() ->
    {ok, Server} = erlmcp_server:start_link(#{
        transport => self(),
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    erlmcp:notify_resource_updated(Server, <<"test://x">>),
    timer:sleep(50),
    ?assert(is_process_alive(Server)),
    gen_server:stop(Server).

start_stdio_setup_test() ->
    {ok, #{server := Server, transport := Transport}} =
        erlmcp:start_stdio_setup(setup_test_srv, #{test_mode => true}),
    ?assert(is_process_alive(Server)),
    ?assert(is_process_alive(Transport)),
    erlmcp_transport_stdio:close(Transport),
    gen_server:stop(Server).

stop_server_dead_process_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, Pid} = erlmcp:start_server(dead_test_srv),
    ok = erlmcp_registry:register_server(dead_test_srv, Pid, #{}),
    gen_statem:stop(Pid),
    timer:sleep(50),
    ok = erlmcp:stop_server(dead_test_srv),
    ok = application:stop(erlmcp),
    timer:sleep(100).

stop_transport_dead_process_test() ->
    {ok, _} = application:ensure_all_started(erlmcp),
    {ok, Pid} = erlmcp:start_transport(dead_t, stdio,
        #{session => self(), test_mode => true}),
    ok = erlmcp_registry:register_transport(dead_t, Pid, #{}),
    erlmcp_transport_stdio:close(Pid),
    timer:sleep(50),
    ok = erlmcp:stop_transport(dead_t),
    ok = application:stop(erlmcp),
    timer:sleep(100).

start_tcp_setup_test() ->
    ok = meck:new(gen_tcp, [unstick, passthrough]),
    FakeSocket = make_ref(),
    meck:expect(gen_tcp, connect, fun(_H, _P, _O, _T) -> {ok, FakeSocket} end),
    meck:expect(gen_tcp, close, fun(_) -> ok end),
    meck:expect(gen_tcp, send, fun(_, _) -> ok end),
    {ok, #{server := Server, transport := Transport}} =
        erlmcp:start_tcp_setup(tcp_test_srv, #{},
            #{host => "localhost", port => 9999}),
    ?assert(is_process_alive(Server)),
    ?assert(is_process_alive(Transport)),
    unlink(Transport),
    erlmcp_transport_tcp:close(Transport),
    gen_statem:stop(Server),
    meck:unload(gen_tcp).

start_http_setup_test() ->
    {ok, #{server := Server, transport := Transport}} =
        erlmcp:start_http_setup(http_test_srv, #{}, #{test_mode => true}),
    ?assert(is_process_alive(Server)),
    ?assert(is_process_alive(Transport)),
    erlmcp_transport_streamable_http:close(Transport),
    gen_server:stop(Server).

init_server_with_transport(Server) ->
    InitReq = erlmcp_json_rpc:encode_request(1, <<"initialize">>, #{
        <<"protocolVersion">> => <<"2025-11-25">>,
        <<"capabilities">> => #{}
    }),
    erlmcp_server_session:send_message(Server, InitReq),
    _ = wait_transport_send(),
    ok.

decode_resp(Json) ->
    {ok, D} = erlmcp_codec:decode(Json), D.

wait_transport_send() ->
    receive {send, Data} -> Data after 5000 -> error(transport_send_timeout) end.
