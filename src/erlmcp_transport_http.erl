-module(erlmcp_transport_http).
-behaviour(gen_server).
-behaviour(erlmcp_transport).

%% Transport behavior callbacks
-export([init/1, send/2, close/1]).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Types
-type http_opts() :: #{
    url := binary() | string(),
    owner := pid(),
    method => get | post,
    headers => [{string() | binary(), string() | binary()}],
    timeout => timeout(),
    connect_timeout => timeout(),
    max_retries => non_neg_integer(),
    retry_delay => pos_integer(),
    ssl_options => [ssl:tls_client_option()],
    http_options => [term()],
    pool_size => pos_integer()
}.

-type state() :: #{
    url := string(),
    owner := pid(),
    method := get | post,
    headers := [{string(), string()}],
    timeout := timeout(),
    connect_timeout := timeout(),
    max_retries := non_neg_integer(),
    retry_delay := pos_integer(),
    http_options := [term()],
    request_options := [term()],
    pending_requests := #{reference() => {pid(), term()}},
    message_queue := queue:queue(binary()),
    pool_size := pos_integer(),
    active_requests := non_neg_integer()
}.

-export_type([http_opts/0]).

%% Default values
-define(DEFAULT_TIMEOUT, 30000).
-define(DEFAULT_CONNECT_TIMEOUT, 5000).
-define(DEFAULT_MAX_RETRIES, 3).
-define(DEFAULT_RETRY_DELAY, 1000).
-define(DEFAULT_POOL_SIZE, 5).
-define(DEFAULT_METHOD, post).

%%====================================================================
%% Transport Behavior Implementation
%%====================================================================

-spec init(http_opts()) -> {ok, state()} | {error, term()}.
init(Opts) when is_map(Opts) ->
    %% Ensure required applications are started
    ensure_apps_started(),
    
    %% Build initial state
    State = build_initial_state(Opts),
    
    %% Return state for transport use
    {ok, State}.

-spec send(state(), iodata()) -> ok | {error, term()}.
send(State, Data) when is_map(State) ->
    gen_server:call(self(), {send_request, Data, State}).

-spec close(state()) -> ok.
close(State) when is_map(State) ->
    %% HTTP is stateless, nothing to close
    ok.

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link(http_opts()) -> {ok, pid()} | {error, term()}.
start_link(Opts) when is_map(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init([http_opts()]) -> {ok, state()}.
init([Opts]) ->
    process_flag(trap_exit, true),
    
    %% Ensure required applications are started
    ensure_apps_started(),
    
    %% Monitor owner
    Owner = maps:get(owner, Opts),
    monitor(process, Owner),
    
    %% Build state
    State = build_initial_state(Opts),
    
    {ok, State}.

-spec handle_call(term(), {pid(), term()}, state()) -> 
    {reply, term(), state()} | {noreply, state()}.

handle_call({send, Data}, From, State) ->
    %% Queue the request
    NewState = enqueue_request(Data, From, State),
    %% Try to process queue
    {noreply, process_request_queue(NewState)};

handle_call({send_request, Data, TransportState}, _From, State) ->
    %% Direct send from transport behavior
    Result = perform_request(Data, TransportState),
    {reply, Result, State};

handle_call(get_state, _From, State) ->
    {reply, {ok, State}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> 
    {noreply, state()} | {stop, term(), state()}.

handle_info({http, {RequestId, Result}}, State) ->
    %% Handle async HTTP response
    {noreply, handle_http_response(RequestId, Result, State)};

handle_info({retry_request, RequestId, Data, Attempt}, State) ->
    %% Retry a failed request
    {noreply, retry_request(RequestId, Data, Attempt, State)};

handle_info({'DOWN', _MonitorRef, process, Owner, Reason}, 
            #{owner := Owner} = State) ->
    logger:info("Owner process ~p died: ~p", [Owner, Reason]),
    {stop, {owner_died, Reason}, State};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #{pending_requests := Pending}) ->
    %% Cancel all pending requests
    maps:foreach(fun(RequestId, _) ->
        httpc:cancel_request(RequestId)
    end, Pending),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions - Initialization
%%====================================================================

-spec ensure_apps_started() -> ok.
ensure_apps_started() ->
    %% Start inets if not already started
    case application:ensure_started(inets) of
        ok -> ok;
        {error, {already_started, inets}} -> ok
    end,
    
    %% Start SSL if needed
    case application:ensure_started(ssl) of
        ok -> ok;
        {error, {already_started, ssl}} -> ok
    end,
    
    %% Start crypto (dependency of SSL)
    case application:ensure_started(crypto) of
        ok -> ok;
        {error, {already_started, crypto}} -> ok
    end,
    
    ok.

-spec build_initial_state(http_opts()) -> state().
build_initial_state(Opts) ->
    Url = normalize_url(maps:get(url, Opts)),
    
    %% Build HTTP options
    HttpOptions = build_http_options(Opts),
    RequestOptions = build_request_options(Opts),
    
    #{
        url => Url,
        owner => maps:get(owner, Opts),
        method => maps:get(method, Opts, ?DEFAULT_METHOD),
        headers => normalize_headers(maps:get(headers, Opts, [])),
        timeout => maps:get(timeout, Opts, ?DEFAULT_TIMEOUT),
        connect_timeout => maps:get(connect_timeout, Opts, ?DEFAULT_CONNECT_TIMEOUT),
        max_retries => maps:get(max_retries, Opts, ?DEFAULT_MAX_RETRIES),
        retry_delay => maps:get(retry_delay, Opts, ?DEFAULT_RETRY_DELAY),
        http_options => HttpOptions,
        request_options => RequestOptions,
        pending_requests => #{},
        message_queue => queue:new(),
        pool_size => maps:get(pool_size, Opts, ?DEFAULT_POOL_SIZE),
        active_requests => 0
    }.

-spec normalize_url(binary() | string()) -> string().
normalize_url(Url) when is_binary(Url) ->
    binary_to_list(Url);
normalize_url(Url) when is_list(Url) ->
    Url.

-spec normalize_headers([{term(), term()}]) -> [{string(), string()}].
normalize_headers(Headers) ->
    DefaultHeaders = [
        {"Content-Type", "application/json"},
        {"Accept", "application/json"},
        {"User-Agent", "erlmcp/1.0"}
    ],
    
    %% Convert and merge headers
    UserHeaders = lists:map(fun({K, V}) ->
        {to_string(K), to_string(V)}
    end, Headers),
    
    %% User headers override defaults
    merge_headers(DefaultHeaders, UserHeaders).

-spec to_string(term()) -> string().
to_string(S) when is_list(S) -> S;
to_string(B) when is_binary(B) -> binary_to_list(B);
to_string(A) when is_atom(A) -> atom_to_list(A);
to_string(I) when is_integer(I) -> integer_to_list(I).

-spec merge_headers([{string(), string()}], [{string(), string()}]) -> 
    [{string(), string()}].
merge_headers(Defaults, User) ->
    %% Create a map from user headers for efficient lookup
    UserMap = maps:from_list([{string:lowercase(K), {K, V}} || {K, V} <- User]),
    
    %% Filter defaults and add all user headers
    Filtered = lists:filter(fun({K, _}) ->
        not maps:is_key(string:lowercase(K), UserMap)
    end, Defaults),
    
    Filtered ++ User.

-spec build_http_options(http_opts()) -> [term()].
build_http_options(Opts) ->
    BaseOptions = [
        {timeout, maps:get(timeout, Opts, ?DEFAULT_TIMEOUT)},
        {connect_timeout, maps:get(connect_timeout, Opts, ?DEFAULT_CONNECT_TIMEOUT)},
        {autoredirect, true},
        {relaxed, true}
    ],
    
    %% Add SSL options if HTTPS
    case maps:get(url, Opts) of
        <<"https://", _/binary>> ->
            SslOpts = maps:get(ssl_options, Opts, []),
            [{ssl, SslOpts} | BaseOptions];
        "https://" ++ _ ->
            SslOpts = maps:get(ssl_options, Opts, []),
            [{ssl, SslOpts} | BaseOptions];
        _ ->
            BaseOptions
    end ++ maps:get(http_options, Opts, []).

-spec build_request_options(http_opts()) -> [term()].
build_request_options(Opts) ->
    [
        {sync, false},  % Always use async for better concurrency
        {stream, self},
        {body_format, binary},
        {full_result, true}
    ].

%%====================================================================
%% Internal functions - Request Handling
%%====================================================================

-spec enqueue_request(binary(), {pid(), term()}, state()) -> state().
enqueue_request(Data, From, State) ->
    %% Add to queue
    NewQueue = queue:in({Data, From}, maps:get(message_queue, State)),
    State#{message_queue := NewQueue}.

-spec process_request_queue(state()) -> state().
process_request_queue(#{active_requests := Active, 
                        pool_size := PoolSize} = State) 
  when Active >= PoolSize ->
    %% Pool is full, wait for completions
    State;
process_request_queue(#{message_queue := Queue} = State) ->
    case queue:out(Queue) of
        {{value, {Data, From}}, NewQueue} ->
            %% Process next request
            NewState = State#{message_queue := NewQueue},
            process_request_queue(send_request(Data, From, NewState));
        {empty, _} ->
            %% No more requests
            State
    end.

-spec send_request(binary(), {pid(), term()}, state()) -> state().
send_request(Data, From, State) ->
    case perform_request(Data, State) of
        {ok, RequestId} ->
            %% Track pending request
            NewPending = maps:put(RequestId, {From, Data, 0}, 
                                  maps:get(pending_requests, State)),
            State#{
                pending_requests := NewPending,
                active_requests := maps:get(active_requests, State) + 1
            };
        {error, Reason} = Error ->
            %% Immediate failure
            gen_server:reply(From, Error),
            logger:error("HTTP request failed immediately: ~p", [Reason]),
            State
    end.

-spec perform_request(binary(), state()) -> {ok, reference()} | {error, term()}.
perform_request(Data, State) ->
    Url = maps:get(url, State),
    Method = maps:get(method, State),
    Headers = maps:get(headers, State),
    HttpOptions = maps:get(http_options, State),
    RequestOptions = maps:get(request_options, State),
    
    Request = case Method of
        post ->
            {Url, Headers, "application/json", Data};
        get ->
            %% For GET, append data as query parameters
            {Url ++ "?" ++ binary_to_list(Data), Headers}
    end,
    
    case httpc:request(Method, Request, HttpOptions, RequestOptions) of
        {ok, RequestId} ->
            {ok, RequestId};
        {error, Reason} = Error ->
            logger:error("Failed to send HTTP request: ~p", [Reason]),
            Error
    end.

-spec handle_http_response(reference(), term(), state()) -> state().
handle_http_response(RequestId, Result, State) ->
    case maps:take(RequestId, maps:get(pending_requests, State)) of
        {{From, Data, Attempts}, NewPending} ->
            NewState = State#{
                pending_requests := NewPending,
                active_requests := max(0, maps:get(active_requests, State) - 1)
            },
            
            %% Process the response
            FinalState = case process_response(Result) of
                {ok, Response} ->
                    %% Success - send to owner and reply
                    maps:get(owner, State) ! {transport_message, Response},
                    gen_server:reply(From, ok),
                    NewState;
                {error, Reason} = Error ->
                    %% Check if we should retry
                    case should_retry(Reason, Attempts, State) of
                        true ->
                            schedule_retry(RequestId, Data, From, Attempts + 1, NewState);
                        false ->
                            gen_server:reply(From, Error),
                            NewState
                    end
            end,
            
            %% Process more requests from queue
            process_request_queue(FinalState);
        error ->
            logger:warning("Received response for unknown request: ~p", [RequestId]),
            State
    end.

-spec process_response(term()) -> {ok, binary()} | {error, term()}.
process_response({ok, {{_Version, StatusCode, _ReasonPhrase}, Headers, Body}})
  when StatusCode >= 200, StatusCode < 300 ->
    %% Success response
    process_body(Body, Headers);
process_response({ok, {{_Version, StatusCode, ReasonPhrase}, _Headers, Body}}) ->
    %% Error response
    logger:error("HTTP error ~p: ~s, Body: ~s", [StatusCode, ReasonPhrase, Body]),
    {error, {http_error, StatusCode, ReasonPhrase}};
process_response({error, Reason}) ->
    {error, {request_failed, Reason}}.

-spec process_body(term(), [{string(), string()}]) -> {ok, binary()} | {error, term()}.
process_body(Body, Headers) when is_binary(Body) ->
    %% Check content type
    case lists:keyfind("content-type", 1, 
                       [{string:lowercase(K), V} || {K, V} <- Headers]) of
        {_, ContentType} ->
            case string:find(ContentType, "application/json") of
                nomatch ->
                    logger:warning("Non-JSON response: ~s", [ContentType]);
                _ ->
                    ok
            end;
        false ->
            ok
    end,
    {ok, Body};
process_body(Body, _Headers) when is_list(Body) ->
    {ok, list_to_binary(Body)};
process_body(Body, _Headers) ->
    {error, {invalid_body_format, Body}}.

-spec should_retry(term(), non_neg_integer(), state()) -> boolean().
should_retry(_Reason, Attempts, #{max_retries := MaxRetries}) 
  when Attempts >= MaxRetries ->
    false;
should_retry({http_error, StatusCode, _}, _Attempts, _State) ->
    %% Retry on server errors and rate limiting
    StatusCode >= 500 orelse StatusCode =:= 429;
should_retry({request_failed, timeout}, _Attempts, _State) ->
    true;
should_retry({request_failed, {failed_connect, _}}, _Attempts, _State) ->
    true;
should_retry(_Reason, _Attempts, _State) ->
    false.

-spec schedule_retry(reference(), binary(), {pid(), term()}, 
                     non_neg_integer(), state()) -> state().
schedule_retry(RequestId, Data, From, Attempts, State) ->
    Delay = calculate_retry_delay(Attempts, State),
    logger:info("Scheduling HTTP retry ~p in ~p ms", [Attempts, Delay]),
    
    erlang:send_after(Delay, self(), {retry_request, RequestId, Data, Attempts}),
    
    %% Put back in pending with updated attempt count
    NewPending = maps:put(RequestId, {From, Data, Attempts}, 
                          maps:get(pending_requests, State)),
    State#{pending_requests := NewPending}.

-spec retry_request(reference(), binary(), non_neg_integer(), state()) -> state().
retry_request(RequestId, Data, Attempts, State) ->
    case maps:get(RequestId, maps:get(pending_requests, State), undefined) of
        {From, Data, _} ->
            %% Remove from pending and resend
            NewPending = maps:remove(RequestId, maps:get(pending_requests, State)),
            NewState = State#{
                pending_requests := NewPending,
                active_requests := max(0, maps:get(active_requests, State) - 1)
            },
            send_request(Data, From, NewState);
        _ ->
            %% Request was cancelled or completed
            State
    end.

-spec calculate_retry_delay(non_neg_integer(), state()) -> pos_integer().
calculate_retry_delay(Attempts, State) ->
    BaseDelay = maps:get(retry_delay, State),
    %% Exponential backoff with jitter
    Backoff = BaseDelay * (1 bsl (Attempts - 1)),
    MaxDelay = 60000,  % 1 minute max
    Jitter = rand:uniform(1000),
    min(Backoff + Jitter, MaxDelay).