-module(erlmcp).

%% Public facade — redesigned in M2. Currently minimal stubs
%% for compilation; the legacy API was removed with the legacy
%% server modules in M1-15.

%% Application management API
-export([start_server/1, start_server/2, stop_server/1, list_servers/0,
         start_transport/2, start_transport/3, stop_transport/1,
         list_transports/0, bind_transport_to_server/2, unbind_transport/1]).
%% Server operations API (M2)
-export([add_resource/3, add_resource/4, add_tool/3, add_tool/4,
         add_prompt/3, add_prompt/4]).
%% Configuration API
-export([get_server_config/1, update_server_config/2,
         get_transport_config/1, update_transport_config/2]).
%% Legacy compatibility (removed)
-export([start_stdio_server/0, start_stdio_server/1, stop_stdio_server/0]).
%% Convenience functions (removed)
-export([start_stdio_setup/2, start_tcp_setup/3, setup_server_components/2,
         quick_stdio_server/3]).

%% Types
-type server_id() :: atom().
-type transport_id() :: atom().
-type transport_type() :: stdio | tcp | http.

-export_type([server_id/0, transport_id/0, transport_type/0]).

%%====================================================================
%% Server management — uses new session model
%%====================================================================

-spec start_server(server_id()) -> {ok, pid()} | {error, term()}.
start_server(ServerId) ->
    start_server(ServerId, #{}).

-spec start_server(server_id(), map()) -> {ok, pid()} | {error, term()}.
start_server(ServerId, Config) ->
    Opts = Config#{name => atom_to_binary(ServerId, utf8)},
    erlmcp_server_session:start_link(Opts).

-spec stop_server(server_id()) -> ok | {error, term()}.
stop_server(ServerId) ->
    case whereis(erlmcp_registry) of
        undefined ->
            {error, registry_not_available};
        _ ->
            case erlmcp_registry:find_server(ServerId) of
                {ok, {ServerPid, _Config}} ->
                    erlmcp_registry:unregister_server(ServerId),
                    case is_process_alive(ServerPid) of
                        true -> gen_statem:stop(ServerPid);
                        false -> ok
                    end;
                {error, not_found} ->
                    ok
            end
    end.

-spec list_servers() -> [{server_id(), {pid(), map()}}].
list_servers() ->
    case whereis(erlmcp_registry) of
        undefined -> [];
        _ -> erlmcp_registry:list_servers()
    end.

%%====================================================================
%% Transport management
%%====================================================================

-spec start_transport(transport_id(), transport_type()) ->
    {ok, pid()} | {error, term()}.
start_transport(TransportId, Type) ->
    start_transport(TransportId, Type, #{}).

-spec start_transport(transport_id(), transport_type(), map()) ->
    {ok, pid()} | {error, term()}.
start_transport(TransportId, stdio, Config) ->
    erlmcp_transport_stdio:start_link(TransportId, Config);
start_transport(_TransportId, Type, _Config) ->
    {error, {transport_not_implemented, Type}}.

-spec stop_transport(transport_id()) -> ok | {error, term()}.
stop_transport(TransportId) ->
    case whereis(erlmcp_registry) of
        undefined ->
            {error, registry_not_available};
        _ ->
            case erlmcp_registry:find_transport(TransportId) of
                {ok, {TransportPid, _Config}} ->
                    erlmcp_registry:unregister_transport(TransportId),
                    case is_process_alive(TransportPid) of
                        true -> erlmcp_transport_stdio:close(TransportPid);
                        false -> ok
                    end;
                {error, not_found} ->
                    ok
            end
    end.

-spec list_transports() -> [{transport_id(), {pid(), map()}}].
list_transports() ->
    case whereis(erlmcp_registry) of
        undefined -> [];
        _ -> erlmcp_registry:list_transports()
    end.

-spec bind_transport_to_server(transport_id(), server_id()) -> ok | {error, term()}.
bind_transport_to_server(TransportId, ServerId) ->
    case whereis(erlmcp_registry) of
        undefined -> {error, registry_not_available};
        _ -> erlmcp_registry:bind_transport_to_server(TransportId, ServerId)
    end.

-spec unbind_transport(transport_id()) -> ok | {error, term()}.
unbind_transport(TransportId) ->
    case whereis(erlmcp_registry) of
        undefined -> {error, registry_not_available};
        _ -> erlmcp_registry:unbind_transport(TransportId)
    end.

%%====================================================================
%% Server operations — stubs for M2
%%====================================================================

-spec add_resource(server_id(), binary(), fun()) -> ok | {error, term()}.
add_resource(_ServerId, _Uri, _Handler) ->
    {error, not_implemented}.

-spec add_resource(server_id(), binary(), binary(), fun()) -> ok | {error, term()}.
add_resource(_ServerId, _Uri, _Name, _Handler) ->
    {error, not_implemented}.

-spec add_tool(server_id(), binary(), fun()) -> ok | {error, term()}.
add_tool(_ServerId, _Name, _Handler) ->
    {error, not_implemented}.

-spec add_tool(server_id(), binary(), fun(), map()) -> ok | {error, term()}.
add_tool(_ServerId, _Name, _Handler, _Schema) ->
    {error, not_implemented}.

-spec add_prompt(server_id(), binary(), fun()) -> ok | {error, term()}.
add_prompt(_ServerId, _Name, _Handler) ->
    {error, not_implemented}.

-spec add_prompt(server_id(), binary(), fun(), [map()]) -> ok | {error, term()}.
add_prompt(_ServerId, _Name, _Handler, _Args) ->
    {error, not_implemented}.

%%====================================================================
%% Configuration — stubs for M2
%%====================================================================

-spec get_server_config(server_id()) -> {ok, map()} | {error, term()}.
get_server_config(_ServerId) -> {error, not_implemented}.

-spec update_server_config(server_id(), map()) -> ok | {error, term()}.
update_server_config(_ServerId, _Config) -> {error, not_implemented}.

-spec get_transport_config(transport_id()) -> {ok, map()} | {error, term()}.
get_transport_config(_TransportId) -> {error, not_implemented}.

-spec update_transport_config(transport_id(), map()) -> ok | {error, term()}.
update_transport_config(_TransportId, _Config) -> {error, not_implemented}.

%%====================================================================
%% Legacy stdio — removed (use start_server + start_transport)
%%====================================================================

-spec start_stdio_server() -> {ok, pid()} | {error, term()}.
start_stdio_server() -> {error, removed}.

-spec start_stdio_server(map()) -> {ok, pid()} | {error, term()}.
start_stdio_server(_Options) -> {error, removed}.

-spec stop_stdio_server() -> ok | {error, term()}.
stop_stdio_server() -> {error, removed}.

%%====================================================================
%% Convenience — stubs
%%====================================================================

-spec start_stdio_setup(server_id(), map()) -> {ok, map()} | {error, term()}.
start_stdio_setup(_ServerId, _Config) -> {error, not_implemented}.

-spec start_tcp_setup(server_id(), map(), map()) -> {ok, map()} | {error, term()}.
start_tcp_setup(_ServerId, _ServerConfig, _TcpConfig) -> {error, not_implemented}.

-spec setup_server_components(pid(), map()) -> ok | {error, term()}.
setup_server_components(_ServerPid, _Config) -> {error, not_implemented}.

-spec quick_stdio_server(binary(), map(), [map()]) -> {ok, map()} | {error, term()}.
quick_stdio_server(_Name, _Caps, _Tools) -> {error, not_implemented}.
