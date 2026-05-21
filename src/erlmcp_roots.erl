-module(erlmcp_roots).

-callback list_roots(erlmcp_ctx:ctx()) ->
    {ok, [map()]} | {error, term()}.
