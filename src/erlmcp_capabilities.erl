-module(erlmcp_capabilities).

-export([
    negotiate_version/2,
    supported_versions/0,
    build_server_capabilities/1,
    build_client_capabilities/1
]).

-define(SUPPORTED_VERSIONS, [<<"2025-11-25">>, <<"2024-11-05">>]).

-spec supported_versions() -> [binary()].
supported_versions() ->
    ?SUPPORTED_VERSIONS.

-spec negotiate_version(binary(), [binary()]) ->
    {ok, binary()} | {error, no_common_version}.
negotiate_version(ClientVersion, ServerVersions) ->
    case lists:member(ClientVersion, ServerVersions) of
        true ->
            {ok, ClientVersion};
        false ->
            {error, no_common_version}
    end.

-spec build_server_capabilities(map()) -> map().
build_server_capabilities(Registered) ->
    maps:fold(
        fun(Key, Opts, Acc) when is_map(Opts) ->
                Acc#{Key => Opts};
           (Key, true, Acc) ->
                Acc#{Key => #{}};
           (_Key, false, Acc) ->
                Acc
        end,
        #{},
        Registered
    ).

-spec build_client_capabilities(map()) -> map().
build_client_capabilities(Registered) ->
    build_server_capabilities(Registered).
