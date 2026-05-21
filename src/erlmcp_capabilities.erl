-module(erlmcp_capabilities).

-export([negotiate/2, build_server/1, build_client/1]).

-spec negotiate(map(), map()) -> {ok, map()} | {error, term()}.
negotiate(_Local, _Remote) ->
    {ok, #{}}.

-spec build_server(map()) -> map().
build_server(_Config) ->
    #{}.

-spec build_client(map()) -> map().
build_client(_Config) ->
    #{}.
