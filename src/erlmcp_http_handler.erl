-module(erlmcp_http_handler).

-export([init/2, info/3, terminate/3]).

-record(state, {
    session_mgr :: pid(),
    server_pid :: pid(),
    replay_buffer_size :: pos_integer(),
    session_id :: binary() | undefined,
    session_pid :: pid() | undefined,
    req_ref :: reference() | undefined,
    mode :: json | sse | get_sse,
    buffer :: erlmcp_http_sse:buffer()
}).

init(Req, Opts) ->
    Method = cowboy_req:method(Req),
    MgrPid = maps:get(session_mgr, Opts),
    ServerPid = maps:get(server_pid, Opts),
    BufSize = maps:get(replay_buffer_size, Opts, 100),
    St = #state{
        session_mgr = MgrPid,
        server_pid = ServerPid,
        replay_buffer_size = BufSize,
        mode = json,
        buffer = erlmcp_http_sse:new_buffer(BufSize)
    },
    case Method of
        <<"POST">> -> handle_post(Req, St);
        <<"GET">> -> handle_get_sse(Req, St);
        <<"DELETE">> -> handle_delete(Req, St);
        _ -> reply_error(405, <<"Method Not Allowed">>, Req, St)
    end.

info({jsonrpc_out, ReqRef, Json}, Req, #state{req_ref = ReqRef, mode = json} = St) ->
    Headers = #{<<"content-type">> => <<"application/json">>},
    Headers1 = add_session_header(Headers, St),
    Req1 = cowboy_req:reply(200, Headers1, Json, Req),
    {stop, Req1, St};

info({sse_event, Json}, Req, #state{mode = get_sse} = St) ->
    {_Id, Formatted, NewBuf} = erlmcp_http_sse:push_event(St#state.buffer, Json),
    cowboy_req:stream_body(Formatted, nofin, Req),
    {ok, Req, St#state{buffer = NewBuf}};

info({'DOWN', _Ref, process, Pid, _Reason},
     Req, #state{session_pid = Pid, mode = json} = St) ->
    Req1 = cowboy_req:reply(502, #{<<"content-type">> => <<"text/plain">>},
                            <<"Session terminated">>, Req),
    {stop, Req1, St};
info({'DOWN', _Ref, process, Pid, _Reason},
     Req, #state{session_pid = Pid} = St) ->
    {stop, Req, St};
info(_Msg, Req, St) ->
    {ok, Req, St}.

terminate(_Reason, _Req, #state{mode = get_sse, session_id = SId,
                                 session_mgr = Mgr}) when SId =/= undefined ->
    erlmcp_http_session_mgr:clear_push_target(Mgr, SId),
    ok;
terminate(_Reason, _Req, _St) ->
    ok.

%%====================================================================
%% POST
%%====================================================================

handle_post(Req, St) ->
    ContentType = cowboy_req:header(<<"content-type">>, Req, <<>>),
    case is_json_content_type(ContentType) of
        false ->
            reply_error(415, <<"Unsupported Media Type">>, Req, St);
        true ->
            {ok, Body, Req1} = cowboy_req:read_body(Req),
            SessionIdHeader = cowboy_req:header(<<"mcp-session-id">>, Req1, undefined),
            handle_post_body(Body, SessionIdHeader, Req1, St)
    end.

handle_post_body(Body, undefined, Req, St) ->
    #state{session_mgr = Mgr} = St,
    {ok, SessionId, SessionPid} = erlmcp_http_session_mgr:mint(Mgr),
    dispatch_to_session(Body, SessionId, SessionPid, Req, St);

handle_post_body(Body, SessionId, Req, St) ->
    #state{session_mgr = Mgr} = St,
    case erlmcp_http_session_mgr:lookup(Mgr, SessionId) of
        {ok, SessionPid} ->
            dispatch_to_session(Body, SessionId, SessionPid, Req, St);
        {error, not_found} ->
            reply_error(404, <<"Session not found">>, Req, St)
    end.

dispatch_to_session(Body, SessionId, SessionPid, Req, St) ->
    case is_notification(Body) of
        true ->
            erlmcp_server_session:send_message(SessionPid, Body),
            Headers = add_session_header(#{}, St#state{session_id = SessionId}),
            Req1 = cowboy_req:reply(202, Headers, <<>>, Req),
            {ok, Req1, St#state{session_id = SessionId}};
        false ->
            ReqRef = make_ref(),
            Responder = erlmcp_reply:new_http(self(), ReqRef),
            monitor(process, SessionPid),
            erlmcp_server_session:send_message(SessionPid, Body, Responder),
            {cowboy_loop, Req,
             St#state{session_id = SessionId, session_pid = SessionPid,
                      req_ref = ReqRef}}
    end.

%%====================================================================
%% GET (SSE stream)
%%====================================================================

handle_get_sse(Req, St) ->
    Accept = cowboy_req:header(<<"accept">>, Req, <<>>),
    case binary:match(Accept, <<"text/event-stream">>) of
        nomatch ->
            reply_error(406, <<"Not Acceptable">>, Req, St);
        _ ->
            SessionId = cowboy_req:header(<<"mcp-session-id">>, Req, undefined),
            handle_get_sse_session(SessionId, Req, St)
    end.

handle_get_sse_session(undefined, Req, St) ->
    reply_error(400, <<"Missing Mcp-Session-Id">>, Req, St);
handle_get_sse_session(SessionId, Req, St) ->
    #state{session_mgr = Mgr} = St,
    case erlmcp_http_session_mgr:lookup(Mgr, SessionId) of
        {ok, SessionPid} ->
            monitor(process, SessionPid),
            LastEventId = cowboy_req:header(<<"last-event-id">>, Req, undefined),
            Headers = #{
                <<"content-type">> => <<"text/event-stream">>,
                <<"cache-control">> => <<"no-cache">>
            },
            Req1 = cowboy_req:stream_reply(200, Headers, Req),
            erlmcp_http_session_mgr:set_push_target(Mgr, SessionId, self()),
            St1 = St#state{session_id = SessionId, session_pid = SessionPid, mode = get_sse},
            case LastEventId of
                undefined ->
                    {cowboy_loop, Req1, St1};
                IdBin ->
                    case catch binary_to_integer(IdBin) of
                        Id when is_integer(Id) ->
                            Events = erlmcp_http_sse:replay_from(St1#state.buffer, Id),
                            lists:foreach(fun(Ev) ->
                                cowboy_req:stream_body(Ev, nofin, Req1)
                            end, Events),
                            {cowboy_loop, Req1, St1};
                        _ ->
                            {cowboy_loop, Req1, St1}
                    end
            end;
        {error, not_found} ->
            reply_error(404, <<"Session not found">>, Req, St)
    end.

%%====================================================================
%% DELETE
%%====================================================================

handle_delete(Req, St) ->
    SessionId = cowboy_req:header(<<"mcp-session-id">>, Req, undefined),
    handle_delete_session(SessionId, Req, St).

handle_delete_session(undefined, Req, St) ->
    reply_error(400, <<"Missing Mcp-Session-Id">>, Req, St);
handle_delete_session(SessionId, Req, St) ->
    #state{session_mgr = Mgr} = St,
    case erlmcp_http_session_mgr:lookup(Mgr, SessionId) of
        {ok, _} ->
            ok = erlmcp_http_session_mgr:evict(Mgr, SessionId),
            Req1 = cowboy_req:reply(200, #{}, <<>>, Req),
            {ok, Req1, St};
        {error, not_found} ->
            reply_error(404, <<"Session not found">>, Req, St)
    end.

%%====================================================================
%% Internal
%%====================================================================

reply_error(Status, Body, Req, St) ->
    Req1 = cowboy_req:reply(Status,
                            #{<<"content-type">> => <<"text/plain">>},
                            Body, Req),
    {ok, Req1, St}.

is_json_content_type(CT) ->
    case binary:match(CT, <<"application/json">>) of
        nomatch -> false;
        _ -> true
    end.

is_notification(Body) ->
    case erlmcp_codec:decode(Body) of
        {ok, Map} when is_map(Map) ->
            not maps:is_key(<<"id">>, Map);
        _ ->
            false
    end.

add_session_header(Headers, #state{session_id = undefined}) ->
    Headers;
add_session_header(Headers, #state{session_id = SId}) ->
    Headers#{<<"mcp-session-id">> => SId}.
