-module(erlmcp_transport_http_tests).

-include_lib("eunit/include/eunit.hrl").

-include("erlmcp.hrl").

%%====================================================================
%% Test fixtures
%%====================================================================

http_transport_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [fun f1_no_calling_self/1, fun f2_send_returns_ok/1, fun f3_initialize_end_to_end/1,
      fun f4_async_response_path/1, fun f5_owner_is_client_pid/1, fun test_binary_url/1,
      fun test_https_url/1, fun test_get_method/1, fun test_custom_headers/1,
      fun test_http_error_response/1, fun test_request_error/1, fun test_retry_on_500/1,
      fun test_no_retry_on_400/1, fun test_retry_exhaustion/1, fun test_pool_limit/1,
      fun test_list_body/1, fun test_invalid_body/1, fun test_close/1, fun test_get_state/1,
      fun test_unknown_request/1, fun test_unknown_info/1, fun test_unknown_response_id/1,
      fun test_httpc_immediate_error/1, fun test_owner_death/1, fun test_code_change/1,
      fun test_handle_cast/1, fun test_terminate_cancels_pending/1, fun test_binary_https_url/1,
      fun test_header_atom_integer_conversion/1, fun test_retry_on_connect_failure/1,
      fun test_retry_cancelled_request/1, fun test_non_json_content_type/1,
      fun test_retry_on_429/1, fun test_list_opts_wrapper/1, fun test_no_content_type_header/1,
      fun test_retry_on_timeout/1, fun test_no_retry_on_unknown_error/1]}.

setup() ->
    ok = meck:new(httpc, [unstick, passthrough]),
    ok.

cleanup(_) ->
    meck:unload(httpc),
    ok.

%%====================================================================
%% F-1: HTTP initialize no longer raises calling_self
%%====================================================================

f1_no_calling_self(_) ->
    {"F-1: HTTP initialize does not crash with calling_self",
     fun() ->
        mock_httpc_async_ok(initialize_response(1)),
        {ok, Client} =
            erlmcp_client:start_link({http, #{url => "http://localhost:9006/mcp"}}, #{}),
        Caps = #mcp_client_capabilities{},
        Result = erlmcp_client:initialize(Client, Caps, #{}),
        ?assertMatch({ok, _}, Result),
        erlmcp_client:stop(Client)
     end}.

%%====================================================================
%% F-2: send/2 returns ok on successful dispatch
%%====================================================================

f2_send_returns_ok(_) ->
    {"F-2: send/2 returns ok (not {ok, Ref})",
     fun() ->
        mock_httpc_async_ok(<<"response body">>),
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        Result = erlmcp_transport_http:send(Pid, <<"test data">>),
        ?assertEqual(ok, Result),
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% F-3: initialize returns {ok, Map} end-to-end
%%====================================================================

f3_initialize_end_to_end(_) ->
    {"F-3: initialize returns {ok, Map} end-to-end",
     fun() ->
        mock_httpc_async_ok(initialize_response(1)),
        {ok, Client} =
            erlmcp_client:start_link({http, #{url => "http://localhost:9006/mcp"}}, #{}),
        Caps = #mcp_client_capabilities{},
        {ok, InitResult} = erlmcp_client:initialize(Client, Caps, #{}),
        ?assertMatch(#{<<"protocolVersion">> := _}, InitResult),
        ?assertMatch(#{<<"capabilities">> := _}, InitResult),
        erlmcp_client:stop(Client)
     end}.

%%====================================================================
%% F-4: async response path works (no stream mismatch)
%%====================================================================

f4_async_response_path(_) ->
    {"F-4: async HTTP response reaches owner as transport_message",
     fun() ->
        Body = <<"hello">>,
        mock_httpc_async_ok(Body),
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"request">>),
        receive
            {transport_message, Received} ->
                ?assertEqual(Body, Received)
        after 2000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% F-5: owner for client's HTTP transport is the client process
%%====================================================================

f5_owner_is_client_pid(_) ->
    {"F-5: client receives transport_message without caller-supplied owner",
     fun() ->
        mock_httpc_async_ok(initialize_response(1)),
        {ok, Client} =
            erlmcp_client:start_link({http, #{url => "http://localhost:9006/mcp"}}, #{}),
        Caps = #mcp_client_capabilities{},
        {ok, _} = erlmcp_client:initialize(Client, Caps, #{}),
        erlmcp_client:stop(Client)
     end}.

%%====================================================================
%% URL handling
%%====================================================================

test_binary_url(_) ->
    {"binary URL is normalized to list",
     fun() ->
        mock_httpc_async_ok(<<"ok">>),
        Opts = #{url => <<"http://localhost:9006/mcp">>, owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, _} ->
                ok
        after 2000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_https_url(_) ->
    {"HTTPS URL adds SSL options",
     fun() ->
        mock_httpc_async_ok(<<"ok">>),
        Opts = #{url => "https://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        {ok, State} = gen_server:call(Pid, get_state),
        HttpOpts = maps:get(http_options, State),
        ?assertMatch({ssl, _}, lists:keyfind(ssl, 1, HttpOpts)),
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% GET method
%%====================================================================

test_get_method(_) ->
    {"GET method appends data as query params",
     fun() ->
        mock_httpc_async_ok(<<"ok">>),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              method => get},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"key=value">>),
        receive
            {transport_message, _} ->
                ok
        after 2000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% Custom headers
%%====================================================================

test_custom_headers(_) ->
    {"custom headers override defaults",
     fun() ->
        mock_httpc_async_ok(<<"ok">>),
        CustomHeaders = [{"Content-Type", "text/plain"}, {<<"X-Custom">>, <<"val">>}],
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              headers => CustomHeaders},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        {ok, State} = gen_server:call(Pid, get_state),
        Headers = maps:get(headers, State),
        ?assertMatch({"Content-Type", "text/plain"}, lists:keyfind("Content-Type", 1, Headers)),
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% Error responses
%%====================================================================

test_http_error_response(_) ->
    {"HTTP 500 error is logged, not delivered as transport_message",
     fun() ->
        mock_httpc_async_error(500, "Internal Server Error"),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 0},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, _} ->
                ?assert(false)
        after 500 ->
            ok
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_request_error(_) ->
    {"httpc request error is handled",
     fun() ->
        mock_httpc_async_request_error(timeout),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 0},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, _} ->
                ?assert(false)
        after 500 ->
            ok
        end,
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% Retry logic
%%====================================================================

test_retry_on_500(_) ->
    {"500 errors trigger retry, success on second attempt",
     fun() ->
        Self = self(),
        AttemptRef = make_ref(),
        Counter = atomics:new(1, [{signed, false}]),
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       Attempt = atomics:add_get(Counter, 1, 1),
                       spawn(fun() ->
                                case Attempt of
                                    1 ->
                                        Self ! {AttemptRef, first_attempt},
                                        Response =
                                            {{"HTTP/1.1", 500, "Internal Server Error"}, [], <<>>},
                                        Caller ! {http, {RequestId, Response}};
                                    _ ->
                                        Response =
                                            {{"HTTP/1.1", 200, "OK"},
                                             [{"content-type", "application/json"}],
                                             <<"retry_success">>},
                                        Caller ! {http, {RequestId, Response}}
                                end
                             end),
                       {ok, RequestId}
                    end),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 3,
              retry_delay => 50},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {AttemptRef, first_attempt} ->
                ok
        after 2000 ->
            ?assert(false)
        end,
        receive
            {transport_message, <<"retry_success">>} ->
                ok
        after 5000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_no_retry_on_400(_) ->
    {"400 errors are not retried",
     fun() ->
        mock_httpc_async_error(400, "Bad Request"),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 3},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, _} ->
                ?assert(false)
        after 500 ->
            ok
        end,
        ?assertEqual(1, meck:num_calls(httpc, request, '_')),
        erlmcp_transport_http:close(Pid)
     end}.

test_retry_exhaustion(_) ->
    {"retries are exhausted after max_retries",
     fun() ->
        mock_httpc_async_error(500, "Internal Server Error"),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 1,
              retry_delay => 50},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        timer:sleep(500),
        receive
            {transport_message, _} ->
                ?assert(false)
        after 100 ->
            ok
        end,
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% Pool limit
%%====================================================================

test_pool_limit(_) ->
    {"requests are queued when pool is full",
     fun() ->
        Counter = atomics:new(1, [{signed, false}]),
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       N = atomics:add_get(Counter, 1, 1),
                       spawn(fun() ->
                                Response =
                                    {{"HTTP/1.1", 200, "OK"},
                                     [{"content-type", "application/json"}],
                                     list_to_binary("resp" ++ integer_to_list(N))},
                                Caller ! {http, {RequestId, Response}}
                             end),
                       {ok, RequestId}
                    end),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              pool_size => 1},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"req1">>),
        ok = erlmcp_transport_http:send(Pid, <<"req2">>),
        receive
            {transport_message, _} ->
                ok
        after 2000 ->
            ?assert(false)
        end,
        receive
            {transport_message, _} ->
                ok
        after 2000 ->
            ?assert(false)
        end,
        ?assertEqual(2, atomics:get(Counter, 1)),
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% Body processing
%%====================================================================

test_list_body(_) ->
    {"list body is converted to binary",
     fun() ->
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       spawn(fun() ->
                                Response =
                                    {{"HTTP/1.1", 200, "OK"},
                                     [{"content-type", "application/json"}],
                                     "list body"},
                                Caller ! {http, {RequestId, Response}}
                             end),
                       {ok, RequestId}
                    end),
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, Body} ->
                ?assertEqual(<<"list body">>, Body)
        after 2000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_invalid_body(_) ->
    {"invalid body format does not crash transport",
     fun() ->
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       spawn(fun() ->
                                Response =
                                    {{"HTTP/1.1", 200, "OK"},
                                     [{"content-type", "application/json"}],
                                     {invalid, body}},
                                Caller ! {http, {RequestId, Response}}
                             end),
                       {ok, RequestId}
                    end),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 0},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, _} ->
                ?assert(false)
        after 500 ->
            ok
        end,
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% gen_server callbacks coverage
%%====================================================================

test_close(_) ->
    {"close/1 stops the transport process",
     fun() ->
        mock_httpc_async_ok(<<"ok">>),
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        erlmcp_transport_http:close(Pid),
        timer:sleep(50),
        ?assertNot(is_process_alive(Pid))
     end}.

test_get_state(_) ->
    {"get_state returns current state map",
     fun() ->
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        {ok, State} = gen_server:call(Pid, get_state),
        ?assertMatch(#{url := _, owner := _}, State),
        erlmcp_transport_http:close(Pid)
     end}.

test_unknown_request(_) ->
    {"unknown gen_server call returns error",
     fun() ->
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ?assertEqual({error, unknown_request}, gen_server:call(Pid, bogus)),
        erlmcp_transport_http:close(Pid)
     end}.

test_unknown_info(_) ->
    {"unknown info message is ignored",
     fun() ->
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        Pid ! some_random_message,
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_http:close(Pid)
     end}.

test_unknown_response_id(_) ->
    {"response for unknown request ID is ignored",
     fun() ->
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        FakeId = make_ref(),
        Pid ! {http, {FakeId, {{"HTTP/1.1", 200, "OK"}, [], <<"body">>}}},
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_http:close(Pid)
     end}.

test_httpc_immediate_error(_) ->
    {"httpc returning immediate error is handled",
     fun() ->
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) -> {error, no_scheme} end),
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, _} ->
                ?assert(false)
        after 200 ->
            ok
        end,
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_http:close(Pid)
     end}.

test_owner_death(_) ->
    {"transport stops when owner dies",
     fun() ->
        Owner =
            spawn(fun() ->
                     receive
                         stop ->
                             ok
                     end
                  end),
        Opts = #{url => "http://localhost:9006/mcp", owner => Owner},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        unlink(Pid),
        MonRef = monitor(process, Pid),
        exit(Owner, kill),
        receive
            {'DOWN', MonRef, process, Pid, {owner_died, killed}} ->
                ok
        after 2000 ->
            ?assert(false)
        end
     end}.

test_code_change(_) ->
    {"code_change returns state unchanged",
     fun() ->
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        {ok, State} = gen_server:call(Pid, get_state),
        ?assertEqual({ok, State}, erlmcp_transport_http:code_change("1.0", State, [])),
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% Additional coverage tests
%%====================================================================

test_handle_cast(_) ->
    {"handle_cast is a no-op",
     fun() ->
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        gen_server:cast(Pid, some_message),
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_http:close(Pid)
     end}.

test_terminate_cancels_pending(_) ->
    {"terminate cancels pending httpc requests",
     fun() ->
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) -> {ok, make_ref()} end),
        meck:expect(httpc, cancel_request, fun(_RequestId) -> ok end),
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data1">>),
        ok = erlmcp_transport_http:send(Pid, <<"data2">>),
        timer:sleep(50),
        erlmcp_transport_http:close(Pid),
        timer:sleep(50),
        ?assert(meck:num_calls(httpc, cancel_request, '_') >= 1)
     end}.

test_binary_https_url(_) ->
    {"binary HTTPS URL adds SSL options",
     fun() ->
        mock_httpc_async_ok(<<"ok">>),
        Opts = #{url => <<"https://localhost:9006/mcp">>, owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        {ok, State} = gen_server:call(Pid, get_state),
        HttpOpts = maps:get(http_options, State),
        ?assertMatch({ssl, _}, lists:keyfind(ssl, 1, HttpOpts)),
        erlmcp_transport_http:close(Pid)
     end}.

test_header_atom_integer_conversion(_) ->
    {"atom and integer header values are converted to strings",
     fun() ->
        mock_httpc_async_ok(<<"ok">>),
        CustomHeaders = [{content_type, 42}],
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              headers => CustomHeaders},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        {ok, State} = gen_server:call(Pid, get_state),
        Headers = maps:get(headers, State),
        ?assertMatch({"content_type", "42"}, lists:keyfind("content_type", 1, Headers)),
        erlmcp_transport_http:close(Pid)
     end}.

test_retry_on_connect_failure(_) ->
    {"failed_connect errors trigger retry",
     fun() ->
        Counter = atomics:new(1, [{signed, false}]),
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       N = atomics:add_get(Counter, 1, 1),
                       spawn(fun() ->
                                case N of
                                    1 ->
                                        Caller
                                        ! {http,
                                           {RequestId,
                                            {error,
                                             {failed_connect,
                                              [{to_address, {"localhost", 9006}}]}}}};
                                    _ ->
                                        Response =
                                            {{"HTTP/1.1", 200, "OK"},
                                             [{"content-type", "application/json"}],
                                             <<"connected">>},
                                        Caller ! {http, {RequestId, Response}}
                                end
                             end),
                       {ok, RequestId}
                    end),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 3,
              retry_delay => 50},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, <<"connected">>} ->
                ok
        after 5000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_retry_cancelled_request(_) ->
    {"retry for cancelled/completed request is a no-op",
     fun() ->
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        FakeRef = make_ref(),
        Pid ! {retry_request, FakeRef, <<"data">>, 1},
        timer:sleep(50),
        ?assert(is_process_alive(Pid)),
        erlmcp_transport_http:close(Pid)
     end}.

test_non_json_content_type(_) ->
    {"non-JSON content type still delivers body with warning",
     fun() ->
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       spawn(fun() ->
                                Response =
                                    {{"HTTP/1.1", 200, "OK"},
                                     [{"Content-Type", "text/plain"}],
                                     <<"plain text">>},
                                Caller ! {http, {RequestId, Response}}
                             end),
                       {ok, RequestId}
                    end),
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, <<"plain text">>} ->
                ok
        after 2000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_retry_on_429(_) ->
    {"429 rate limit triggers retry",
     fun() ->
        Counter = atomics:new(1, [{signed, false}]),
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       N = atomics:add_get(Counter, 1, 1),
                       spawn(fun() ->
                                case N of
                                    1 ->
                                        Response =
                                            {{"HTTP/1.1", 429, "Too Many Requests"}, [], <<>>},
                                        Caller ! {http, {RequestId, Response}};
                                    _ ->
                                        Response =
                                            {{"HTTP/1.1", 200, "OK"},
                                             [{"content-type", "application/json"}],
                                             <<"rate_ok">>},
                                        Caller ! {http, {RequestId, Response}}
                                end
                             end),
                       {ok, RequestId}
                    end),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 3,
              retry_delay => 50},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, <<"rate_ok">>} ->
                ok
        after 5000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_list_opts_wrapper(_) ->
    {"client accepts {http, [MapOpts]} list wrapper",
     fun() ->
        mock_httpc_async_ok(initialize_response(1)),
        {ok, Client} =
            erlmcp_client:start_link({http, [#{url => "http://localhost:9006/mcp"}]}, #{}),
        Caps = #mcp_client_capabilities{},
        {ok, _} = erlmcp_client:initialize(Client, Caps, #{}),
        erlmcp_client:stop(Client)
     end}.

test_no_content_type_header(_) ->
    {"response without content-type header still delivers body",
     fun() ->
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       spawn(fun() ->
                                Response = {{"HTTP/1.1", 200, "OK"}, [], <<"no ct">>},
                                Caller ! {http, {RequestId, Response}}
                             end),
                       {ok, RequestId}
                    end),
        Opts = #{url => "http://localhost:9006/mcp", owner => self()},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, <<"no ct">>} ->
                ok
        after 2000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_retry_on_timeout(_) ->
    {"timeout errors trigger retry and succeed on second attempt",
     fun() ->
        Counter = atomics:new(1, [{signed, false}]),
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       N = atomics:add_get(Counter, 1, 1),
                       spawn(fun() ->
                                case N of
                                    1 ->
                                        Caller ! {http, {RequestId, {error, timeout}}};
                                    _ ->
                                        Response =
                                            {{"HTTP/1.1", 200, "OK"},
                                             [{"content-type", "application/json"}],
                                             <<"timeout_ok">>},
                                        Caller ! {http, {RequestId, Response}}
                                end
                             end),
                       {ok, RequestId}
                    end),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 3,
              retry_delay => 50},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, <<"timeout_ok">>} ->
                ok
        after 5000 ->
            ?assert(false)
        end,
        erlmcp_transport_http:close(Pid)
     end}.

test_no_retry_on_unknown_error(_) ->
    {"unknown error types are not retried",
     fun() ->
        meck:expect(httpc,
                    request,
                    fun(_Method, _Request, _HttpOptions, _Options) ->
                       RequestId = make_ref(),
                       Caller = self(),
                       spawn(fun() -> Caller ! {http, {RequestId, {error, some_weird_error}}} end),
                       {ok, RequestId}
                    end),
        Opts =
            #{url => "http://localhost:9006/mcp",
              owner => self(),
              max_retries => 3},
        {ok, Pid} = erlmcp_transport_http:start_link(Opts),
        ok = erlmcp_transport_http:send(Pid, <<"data">>),
        receive
            {transport_message, _} ->
                ?assert(false)
        after 500 ->
            ok
        end,
        ?assertEqual(1, meck:num_calls(httpc, request, '_')),
        erlmcp_transport_http:close(Pid)
     end}.

%%====================================================================
%% Helpers
%%====================================================================

mock_httpc_async_ok(ResponseBody) ->
    meck:expect(httpc,
                request,
                fun(_Method, _Request, _HttpOptions, _Options) ->
                   RequestId = make_ref(),
                   Caller = self(),
                   spawn(fun() ->
                            Response =
                                {{"HTTP/1.1", 200, "OK"},
                                 [{"content-type", "application/json"}],
                                 ResponseBody},
                            Caller ! {http, {RequestId, Response}}
                         end),
                   {ok, RequestId}
                end).

mock_httpc_async_error(StatusCode, ReasonPhrase) ->
    meck:expect(httpc,
                request,
                fun(_Method, _Request, _HttpOptions, _Options) ->
                   RequestId = make_ref(),
                   Caller = self(),
                   spawn(fun() ->
                            Response = {{"HTTP/1.1", StatusCode, ReasonPhrase}, [], <<>>},
                            Caller ! {http, {RequestId, Response}}
                         end),
                   {ok, RequestId}
                end).

mock_httpc_async_request_error(Reason) ->
    meck:expect(httpc,
                request,
                fun(_Method, _Request, _HttpOptions, _Options) ->
                   RequestId = make_ref(),
                   Caller = self(),
                   spawn(fun() -> Caller ! {http, {RequestId, {error, Reason}}} end),
                   {ok, RequestId}
                end).

initialize_response(Id) ->
    erlmcp_json_rpc:encode_response(Id,
                                    #{<<"protocolVersion">> => <<"2025-06-18">>,
                                      <<"capabilities">> =>
                                          #{<<"tools">> => #{}, <<"resources">> => #{}},
                                      <<"serverInfo">> =>
                                          #{<<"name">> => <<"test-server">>,
                                            <<"version">> => <<"1.0.0">>}}).
