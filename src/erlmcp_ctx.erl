-module(erlmcp_ctx).

-opaque ctx() :: #{
    session := pid(),
    transport := pid() | undefined,
    request_id := term(),
    progress_token => binary() | integer(),
    meta => map()
}.

-export_type([ctx/0]).

-export([new/1, session/1, transport/1, request_id/1,
         progress_token/1, meta/1, report_progress/3]).

-spec new(map()) -> ctx().
new(Opts) when is_map(Opts) ->
    Base = #{session => maps:get(session, Opts),
             transport => maps:get(transport, Opts, undefined),
             request_id => maps:get(request_id, Opts)},
    maybe_add(progress_token, Opts,
    maybe_add(meta, Opts, Base)).

maybe_add(Key, Opts, Acc) ->
    case maps:get(Key, Opts, undefined) of
        undefined -> Acc;
        Value -> Acc#{Key => Value}
    end.

-spec session(ctx()) -> pid().
session(#{session := Pid}) -> Pid.

-spec transport(ctx()) -> pid() | undefined.
transport(#{transport := Pid}) -> Pid.

-spec request_id(ctx()) -> term().
request_id(#{request_id := Id}) -> Id.

-spec progress_token(ctx()) -> binary() | integer() | undefined.
progress_token(Ctx) -> maps:get(progress_token, Ctx, undefined).

-spec meta(ctx()) -> map().
meta(Ctx) -> maps:get(meta, Ctx, #{}).

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
