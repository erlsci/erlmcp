-module(erlmcp_facade_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Tool API
%%====================================================================

add_tool_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
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
    [Tool] = erlmcp_server_session:list_tools(Server),
    ?assertEqual(<<"t">>, maps:get(name, Tool)),
    gen_statem:stop(Server).

remove_tool_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp:add_tool(Server, #{
        name => <<"t">>, description => <<"t">>,
        input_schema => erlmcp_schema:object([]),
        handler => fun(_, _) -> {ok, erlmcp:text(<<"ok">>)} end
    }),
    ok = erlmcp:remove_tool(Server, <<"t">>),
    ?assertEqual([], erlmcp_server_session:list_tools(Server)),
    gen_statem:stop(Server).

register_handler_test() ->
    {ok, Server} = erlmcp_server_session:start_link(#{
        name => <<"test">>, version => <<"1.0">>, capabilities => #{}
    }),
    ok = erlmcp:register_handler(Server, test_calc_handler),
    Tools = erlmcp_server_session:list_tools(Server),
    ?assert(length(Tools) > 0),
    gen_statem:stop(Server).

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
    {ok, Server} = erlmcp_server_session:start_link(#{
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
    gen_statem:stop(Server).

%%====================================================================
%% Server management (existing functional code)
%%====================================================================

start_stop_server_test() ->
    {ok, Pid} = erlmcp:start_server(test_srv),
    ?assert(is_process_alive(Pid)),
    gen_statem:stop(Pid).

start_server_with_config_test() ->
    {ok, Pid} = erlmcp:start_server(test_srv2, #{version => <<"2.0">>}),
    ?assert(is_process_alive(Pid)),
    gen_statem:stop(Pid).

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
%% Stubs that return not_implemented
%%====================================================================

add_resource_stub_test() ->
    ?assertEqual({error, not_implemented}, erlmcp:add_resource(x, <<"u">>, fun() -> ok end)),
    ?assertEqual({error, not_implemented}, erlmcp:add_resource(x, <<"u">>, <<"n">>, fun() -> ok end)).

add_prompt_stub_test() ->
    ?assertEqual({error, not_implemented}, erlmcp:add_prompt(x, <<"p">>, fun() -> ok end)),
    ?assertEqual({error, not_implemented}, erlmcp:add_prompt(x, <<"p">>, fun() -> ok end, [])).
