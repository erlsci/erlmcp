-module(erlmcp_elicitation).

-callback handle_elicit(map(), erlmcp_ctx:ctx()) ->
    {ok, map()} | {error, term()}.
