-module(erlmcp_ctx).

-opaque ctx() :: #{
    session := pid(),
    request_id := term(),
    server_ref => ets:tid(),
    progress_token => binary() | integer(),
    meta => map(),
    peer_timeout => timeout()
}.

-export_type([ctx/0]).

-export([new/1, session/1, request_id/1, server_ref/1,
         progress_token/1, meta/1, peer_timeout/1,
         report_progress/3, request_peer/3]).

-spec new(map()) -> ctx().
new(Opts) when is_map(Opts) ->
    Base = #{session => maps:get(session, Opts),
             request_id => maps:get(request_id, Opts)},
    maybe_add(server_ref, Opts,
    maybe_add(peer_timeout, Opts,
    maybe_add(progress_token, Opts,
    maybe_add(meta, Opts, Base)))).

maybe_add(Key, Opts, Acc) ->
    case maps:get(Key, Opts, undefined) of
        undefined -> Acc;
        Value -> Acc#{Key => Value}
    end.

-spec session(ctx()) -> pid().
session(#{session := Pid}) -> Pid.

-spec request_id(ctx()) -> term().
request_id(#{request_id := Id}) -> Id.

-spec server_ref(ctx()) -> ets:tid() | undefined.
server_ref(Ctx) -> maps:get(server_ref, Ctx, undefined).

-spec progress_token(ctx()) -> binary() | integer() | undefined.
progress_token(Ctx) -> maps:get(progress_token, Ctx, undefined).

-spec meta(ctx()) -> map().
meta(Ctx) -> maps:get(meta, Ctx, #{}).

-spec peer_timeout(ctx()) -> timeout().
peer_timeout(Ctx) -> maps:get(peer_timeout, Ctx, 30000).

-spec request_peer(ctx(), binary(), map()) -> {ok, map()} | {error, term()}.
request_peer(#{session := Session} = Ctx, Method, Params) ->
    Ref = make_ref(),
    Timeout = peer_timeout(Ctx),
    Session ! {peer_request, self(), Ref, Method, Params},
    receive
        {peer_response, Ref, Result} -> Result
    after Timeout ->
        {error, timeout}
    end.

-spec report_progress(ctx(), float(), binary()) -> ok.
report_progress(#{session := Session, request_id := ReqId} = Ctx, Fraction, Msg) ->
    case progress_token(Ctx) of
        undefined ->
            ok;
        Token ->
            Params = #{
                <<"progressToken">> => Token,
                <<"progress">> => Fraction,
                <<"total">> => 1.0,
                <<"message">> => Msg
            },
            Notification = erlmcp_json_rpc:encode_notification(
                               <<"notifications/progress">>, Params),
            _ = Session ! {send_notification, ReqId, Notification},
            ok
    end.
