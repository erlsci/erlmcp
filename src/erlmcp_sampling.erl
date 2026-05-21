-module(erlmcp_sampling).

-callback handle_create_message(map(), erlmcp_ctx:ctx()) ->
    {ok, map()} | {error, term()}.
