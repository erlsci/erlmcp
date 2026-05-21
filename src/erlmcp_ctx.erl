-module(erlmcp_ctx).

-opaque ctx() :: map().

-export_type([ctx/0]).

-export([new/1, report_progress/3]).

-spec new(map()) -> ctx().
new(Opts) when is_map(Opts) ->
    Opts.

-spec report_progress(ctx(), float(), binary()) -> ok.
report_progress(_Ctx, _Fraction, _Msg) ->
    ok.
