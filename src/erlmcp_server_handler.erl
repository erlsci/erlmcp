-module(erlmcp_server_handler).

-callback tools() -> [map()].
-callback handle_tool(binary(), map(), erlmcp_ctx:ctx()) ->
    {ok, term()} | {error, integer(), binary()}.

-optional_callbacks([tools/0, handle_tool/3]).
