-module(erlmcp).

-include("erlmcp.hrl").

%% Application management API
-export([start_server/1, start_server/2, stop_server/1, list_servers/0, start_transport/2,
         start_transport/3, stop_transport/1, list_transports/0, bind_transport_to_server/2,
         unbind_transport/1]).
%% Server operations API
-export([add_resource/3, add_resource/4, add_tool/3, add_tool/4, add_prompt/3,
         add_prompt/4]).
%% Configuration API
-export([get_server_config/1, update_server_config/2, get_transport_config/1,
         update_transport_config/2]).
%% Legacy compatibility for stdio server
-export([start_stdio_server/0, start_stdio_server/1, stop_stdio_server/0]).
%% Convenience functions
-export([start_stdio_setup/2, start_tcp_setup/3, setup_server_components/2,
         quick_stdio_server/3]).

%% Types
-type server_id() :: atom().
-type transport_id() :: atom().
-type transport_type() :: stdio | tcp | http.

-export_type([server_id/0, transport_id/0, transport_type/0]).

%%====================================================================
%% Application Management API - Updated for Phase 2
%%====================================================================

-spec start_server(server_id()) -> {ok, pid()} | {error, term()}.
start_server(ServerId) ->
    start_server(ServerId, #{}).

-spec start_server(server_id(), map()) -> {ok, pid()} | {error, term()}.
start_server(ServerId, Config) ->
    % Ensure default capabilities if not provided
    DefaultCaps =
        #mcp_server_capabilities{resources = #mcp_capability{enabled = true},
                                 tools = #mcp_capability{enabled = true},
                                 prompts = #mcp_capability{enabled = true}},

    % Merge with provided config
    FinalConfig =
        case maps:get(capabilities, Config, undefined) of
            undefined ->
                Config#{capabilities => DefaultCaps};
            _ ->
                Config
        end,

    % Start server using the refactored erlmcp_server
    case start_server_process(ServerId, FinalConfig) of
        {ok, ServerPid} ->
            % Register with registry if available
            case register_server_with_registry(ServerId, ServerPid, FinalConfig) of
                ok ->
                    logger:info("Started and registered server ~p", [ServerId]),
                    {ok, ServerPid};
                {error, Reason} ->
                    % Registration failed, but server started - log warning and continue
                    logger:warning("Server ~p started but registry registration failed: ~p",
                                   [ServerId, Reason]),
                    {ok, ServerPid}
            end;
        {error, _} = Error ->
            Error
    end.

-spec stop_server(server_id()) -> ok | {error, term()}.
stop_server(ServerId) ->
    % Try registry approach first
    case whereis(erlmcp_registry) of
        undefined ->
            % No registry, try to find server process by registered name or other means
            logger:warning("Registry not available for server ~p cleanup", [ServerId]),
            {error, registry_not_available};
        _ ->
            case erlmcp_registry:find_server(ServerId) of
                {ok, {ServerPid, _Config}} ->
                    erlmcp_registry:unregister_server(ServerId),
                    case is_process_alive(ServerPid) of
                        true ->
                            erlmcp_server:stop(ServerPid),
                            logger:info("Stopped server ~p", [ServerId]),
                            ok;
                        false ->
                            logger:info("Server ~p already stopped", [ServerId]),
                            ok
                    end;
                {error, not_found} ->
                    logger:warning("Server ~p not found in registry", [ServerId]),
                    ok
            end
    end.

-spec list_servers() -> [{server_id(), {pid(), map()}}].
list_servers() ->
    case whereis(erlmcp_registry) of
        undefined ->
            logger:warning("Registry not available for listing servers"),
            [];
        _ ->
            erlmcp_registry:list_servers()
    end.

-spec start_transport(transport_id(), transport_type()) -> {ok, pid()} | {error, term()}.
start_transport(TransportId, Type) ->
    start_transport(TransportId, Type, #{}).

-spec start_transport(transport_id(), transport_type(), map()) ->
                         {ok, pid()} | {error, term()}.
start_transport(TransportId, Type, Config) ->
    case Type of
        stdio ->
            case erlmcp_transport_stdio_new:start_link(TransportId, Config) of
                {ok, TransportPid} ->
                    TransportConfig = Config#{type => Type},
                    case register_transport_with_registry(TransportId,
                                                          TransportPid,
                                                          TransportConfig)
                    of
                        ok ->
                            logger:info("Started and registered transport ~p", [TransportId]),
                            {ok, TransportPid};
                        {error, Reason} ->
                            logger:warning("Transport ~p started but registry registration failed: ~p",
                                           [TransportId, Reason]),
                            {ok, TransportPid}
                    end;
                Error ->
                    Error
            end;
        tcp ->
            {error, {transport_not_implemented, tcp}};
        http ->
            {error, {transport_not_implemented, http}};
        _ ->
            {error, {unknown_transport_type, Type}}
    end.

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
                        true ->
                            erlmcp_transport_stdio_new:close(TransportPid),
                            logger:info("Stopped transport ~p", [TransportId]),
                            ok;
                        false ->
                            ok
                    end;
                {error, not_found} ->
                    ok
            end
    end.

-spec list_transports() -> [{transport_id(), {pid(), map()}}].
list_transports() ->
    case whereis(erlmcp_registry) of
        undefined ->
            [];
        _ ->
            erlmcp_registry:list_transports()
    end.

-spec bind_transport_to_server(transport_id(), server_id()) -> ok | {error, term()}.
bind_transport_to_server(TransportId, ServerId) ->
    case whereis(erlmcp_registry) of
        undefined ->
            {error, registry_not_available};
        _ ->
            erlmcp_registry:bind_transport_to_server(TransportId, ServerId)
    end.

-spec unbind_transport(transport_id()) -> ok.
unbind_transport(TransportId) ->
    case whereis(erlmcp_registry) of
        undefined ->
            {error, registry_not_available};
        _ ->
            erlmcp_registry:unbind_transport(TransportId)
    end.

%%====================================================================
%% Server Operations API - Updated for Registry-based Architecture
%%====================================================================

-spec add_resource(server_id(), binary(), fun()) -> ok | {error, term()}.
add_resource(ServerId, Uri, Handler) ->
    add_resource(ServerId, Uri, Handler, #{}).

-spec add_resource(server_id(), binary(), fun(), map()) -> ok | {error, term()}.
add_resource(ServerId, Uri, Handler, Options) ->
    case find_server_process(ServerId) of
        {ok, ServerPid} ->
            case maps:get(template, Options, false) of
                true ->
                    Name = maps:get(name, Options, Uri),
                    erlmcp_server:add_resource_template(ServerPid, Uri, Name, Handler);
                false ->
                    erlmcp_server:add_resource(ServerPid, Uri, Handler)
            end;
        {error, not_found} ->
            {error, server_not_found}
    end.

-spec add_tool(server_id(), binary(), fun()) -> ok | {error, term()}.
add_tool(ServerId, Name, Handler) ->
    add_tool(ServerId, Name, Handler, #{}).

-spec add_tool(server_id(), binary(), fun(), map()) -> ok | {error, term()}.
add_tool(ServerId, Name, Handler, Options) ->
    case find_server_process(ServerId) of
        {ok, ServerPid} ->
            case maps:get(schema, Options, undefined) of
                undefined ->
                    erlmcp_server:add_tool(ServerPid, Name, Handler);
                Schema ->
                    erlmcp_server:add_tool_with_schema(ServerPid, Name, Handler, Schema)
            end;
        {error, not_found} ->
            {error, server_not_found}
    end.

-spec add_prompt(server_id(), binary(), fun()) -> ok | {error, term()}.
add_prompt(ServerId, Name, Handler) ->
    add_prompt(ServerId, Name, Handler, #{}).

-spec add_prompt(server_id(), binary(), fun(), map()) -> ok | {error, term()}.
add_prompt(ServerId, Name, Handler, Options) ->
    case find_server_process(ServerId) of
        {ok, ServerPid} ->
            case maps:get(arguments, Options, undefined) of
                undefined ->
                    erlmcp_server:add_prompt(ServerPid, Name, Handler);
                Arguments ->
                    erlmcp_server:add_prompt_with_args(ServerPid, Name, Handler, Arguments)
            end;
        {error, not_found} ->
            {error, server_not_found}
    end.

%%====================================================================
%% Configuration API
%%====================================================================

-spec get_server_config(server_id()) -> {ok, map()} | {error, term()}.
get_server_config(ServerId) ->
    case whereis(erlmcp_registry) of
        undefined ->
            {error, registry_not_available};
        _ ->
            case erlmcp_registry:find_server(ServerId) of
                {ok, {_ServerPid, Config}} ->
                    {ok, Config};
                {error, not_found} ->
                    {error, server_not_found}
            end
    end.

-spec update_server_config(server_id(), map()) -> ok | {error, term()}.
update_server_config(ServerId, NewConfig) ->
    case whereis(erlmcp_registry) of
        undefined ->
            {error, registry_not_available};
        _ ->
            case erlmcp_registry:find_server(ServerId) of
                {ok, {ServerPid, OldConfig}} ->
                    UpdatedConfig = maps:merge(OldConfig, NewConfig),
                    erlmcp_registry:register_server(ServerId, ServerPid, UpdatedConfig);
                {error, not_found} ->
                    {error, server_not_found}
            end
    end.

-spec get_transport_config(transport_id()) -> {ok, map()} | {error, term()}.
get_transport_config(TransportId) ->
    case whereis(erlmcp_registry) of
        undefined ->
            {error, registry_not_available};
        _ ->
            case erlmcp_registry:find_transport(TransportId) of
                {ok, {_TransportPid, Config}} ->
                    {ok, Config};
                {error, not_found} ->
                    {error, transport_not_found}
            end
    end.

-spec update_transport_config(transport_id(), map()) -> ok | {error, term()}.
update_transport_config(TransportId, NewConfig) ->
    case whereis(erlmcp_registry) of
        undefined ->
            {error, registry_not_available};
        _ ->
            case erlmcp_registry:find_transport(TransportId) of
                {ok, {TransportPid, OldConfig}} ->
                    UpdatedConfig = maps:merge(OldConfig, NewConfig),
                    erlmcp_registry:register_transport(TransportId, TransportPid, UpdatedConfig);
                {error, not_found} ->
                    {error, transport_not_found}
            end
    end.

%%====================================================================
%% Legacy Compatibility API - Enhanced for Phase 2
%%====================================================================

-spec start_stdio_server() -> {ok, pid()} | {error, term()}.
start_stdio_server() ->
    start_stdio_server(#{}).

-spec start_stdio_server(map()) -> {ok, pid()} | {error, term()}.
start_stdio_server(Options) ->
    % Use the new architecture by default, fall back to legacy if needed
    case is_new_architecture_available() of
        true ->
            % Use new registry-based approach
            case start_stdio_setup(default_stdio_server, Options) of
                {ok, #{server := ServerPid}} ->
                    {ok, ServerPid};
                {error, _} = Error ->
                    % Fall back to legacy approach
                    logger:warning("New stdio setup failed, falling back to legacy: ~p", [Error]),
                    start_legacy_stdio_server(Options)
            end;
        false ->
            % Registry not available, use legacy approach
            start_legacy_stdio_server(Options)
    end.

-spec stop_stdio_server() -> ok.
stop_stdio_server() ->
    % Try new architecture first
    case is_new_architecture_available() of
        true ->
            _ = stop_transport(default_stdio_transport),
            _ = stop_server(default_stdio_server),
            % Also stop legacy server if it exists
            stop_legacy_stdio_server(),
            ok;
        false ->
            % Fall back to legacy approach
            stop_legacy_stdio_server(),
            ok
    end.

%%====================================================================
%% Convenience Functions - Updated for Phase 2
%%====================================================================

%% Create a complete MCP server setup with stdio transport
-spec start_stdio_setup(server_id(), map()) ->
                           {ok, #{server => pid(), transport => pid()}} | {error, term()}.
start_stdio_setup(ServerId, Config) ->
    case start_server(ServerId, Config) of
        {ok, ServerPid} ->
            TransportId = create_transport_id(ServerId, <<"stdio">>),
            TransportConfig = #{server_id => ServerId},
            case start_transport(TransportId, stdio, TransportConfig) of
                {ok, TransportPid} ->
                    % Ensure they're bound together
                    case bind_transport_to_server(TransportId, ServerId) of
                        ok ->
                            {ok, #{server => ServerPid, transport => TransportPid}};
                        {error, BindError} ->
                            logger:warning("Server and transport started but binding failed: ~p",
                                           [BindError]),
                            {ok, #{server => ServerPid, transport => TransportPid}}
                    end;
                {error, TransportError} ->
                    _ = stop_server(ServerId),
                    {error, TransportError}
            end;
        {error, _} = ServerError ->
            ServerError
    end.

%% Create a complete MCP server setup with TCP transport
-spec start_tcp_setup(server_id(), map(), map()) ->
                         {ok, #{server => pid(), transport => pid()}} | {error, term()}.
start_tcp_setup(ServerId, ServerConfig, TcpConfig) ->
    case start_server(ServerId, ServerConfig) of
        {ok, ServerPid} ->
            TransportId = create_transport_id(ServerId, <<"tcp">>),
            TransportConfig = maps:merge(#{server_id => ServerId}, TcpConfig),
            case start_transport(TransportId, tcp, TransportConfig) of
                {ok, TransportPid} ->
                    case bind_transport_to_server(TransportId, ServerId) of
                        ok ->
                            {ok, #{server => ServerPid, transport => TransportPid}};
                        {error, BindError} ->
                            logger:warning("Server and transport started but binding failed: ~p",
                                           [BindError]),
                            {ok, #{server => ServerPid, transport => TransportPid}}
                    end;
                {error, TransportError} ->
                    _ = stop_server(ServerId),
                    {error, TransportError}
            end;
        {error, _} = ServerError ->
            ServerError
    end.

%% Batch add multiple resources, tools, and prompts
-spec setup_server_components(server_id(), map()) -> ok | {error, term()}.
setup_server_components(ServerId, Components) ->
    Resources = maps:get(resources, Components, []),
    Tools = maps:get(tools, Components, []),
    Prompts = maps:get(prompts, Components, []),

    try
        % Add resources
        lists:foreach(fun ({Uri, Handler}) ->
                              ok = add_resource(ServerId, Uri, Handler);
                          ({Uri, Handler, Options}) ->
                              ok = add_resource(ServerId, Uri, Handler, Options)
                      end,
                      Resources),

        % Add tools
        lists:foreach(fun ({Name, Handler}) ->
                              ok = add_tool(ServerId, Name, Handler);
                          ({Name, Handler, Options}) ->
                              ok = add_tool(ServerId, Name, Handler, Options)
                      end,
                      Tools),

        % Add prompts
        lists:foreach(fun ({Name, Handler}) ->
                              ok = add_prompt(ServerId, Name, Handler);
                          ({Name, Handler, Options}) ->
                              ok = add_prompt(ServerId, Name, Handler, Options)
                      end,
                      Prompts),

        ok
    catch
        error:{badmatch, {error, Reason}} ->
            {error, Reason};
        Class:Exception ->
            {error, {Class, Exception}}
    end.

%% Quick way to create a complete stdio MCP server with components
-spec quick_stdio_server(server_id(), map(), map()) ->
                            {ok, #{server => pid(), transport => pid()}} | {error, term()}.
quick_stdio_server(ServerId, ServerConfig, Components) ->
    case start_stdio_setup(ServerId, ServerConfig) of
        {ok, Result} ->
            case setup_server_components(ServerId, Components) of
                ok ->
                    {ok, Result};
                {error, SetupError} ->
                    TransportId = create_transport_id(ServerId, <<"stdio">>),
                    _ = stop_server(ServerId),
                    _ = stop_transport(TransportId),
                    {error, SetupError}
            end;
        {error, _} = Error ->
            Error
    end.

%%====================================================================
%% Internal Helper Functions - Phase 2 Specific
%%====================================================================

-spec start_server_process(server_id(), map()) -> {ok, pid()} | {error, term()}.
start_server_process(ServerId, Config) ->
    % Try supervisor approach first, fall back to direct start
    case whereis(erlmcp_server_sup) of
        undefined ->
            % Supervisor not available, create server directly
            Capabilities = maps:get(capabilities, Config, #mcp_server_capabilities{}),
            erlmcp_server:start_link(ServerId, Capabilities);
        _Pid ->
            % Use supervisor
            erlmcp_server_sup:start_child(ServerId, Config)
    end.

-spec register_server_with_registry(server_id(), pid(), map()) -> ok | {error, term()}.
register_server_with_registry(ServerId, ServerPid, Config) ->
    case whereis(erlmcp_registry) of
        undefined ->
            % Registry not available - this is OK for some deployments
            ok;
        _ ->
            erlmcp_registry:register_server(ServerId, ServerPid, Config)
    end.

-spec register_transport_with_registry(transport_id(), pid(), map()) ->
                                          ok | {error, term()}.
register_transport_with_registry(TransportId, TransportPid, Config) ->
    case whereis(erlmcp_registry) of
        undefined ->
            ok; % Registry not available - this is OK
        _ ->
            erlmcp_registry:register_transport(TransportId, TransportPid, Config)
    end.

-spec find_server_process(server_id()) -> {ok, pid()} | {error, not_found}.
find_server_process(ServerId) ->
    case whereis(erlmcp_registry) of
        undefined ->
            % Registry not available, try other approaches
            {error, registry_not_available};
        _ ->
            case erlmcp_registry:find_server(ServerId) of
                {ok, {ServerPid, _Config}} ->
                    {ok, ServerPid};
                {error, not_found} ->
                    {error, not_found}
            end
    end.

-spec is_new_architecture_available() -> boolean().
is_new_architecture_available() ->
    whereis(erlmcp_registry) =/= undefined
    andalso whereis(erlmcp_server_sup) =/= undefined
    andalso whereis(erlmcp_transport_sup) =/= undefined.

-spec create_transport_id(server_id(), binary()) -> transport_id().
create_transport_id(ServerId, Type) ->
    binary_to_atom(<<(atom_to_binary(ServerId))/binary, "_", Type/binary>>, utf8).

%%====================================================================
%% Legacy Support Functions
%%====================================================================

-spec start_legacy_stdio_server(map()) -> {ok, pid()} | {error, term()}.
start_legacy_stdio_server(Options) ->
    case erlmcp_stdio_server:start_link(Options) of
        {ok, ServerPid} ->
            % Register as default stdio server if registry is available
            case whereis(erlmcp_registry) of
                undefined ->
                    {ok, ServerPid};
                _ ->
                    ServerConfig =
                        #{capabilities =>
                              #mcp_server_capabilities{resources = #mcp_capability{enabled = true},
                                                       tools = #mcp_capability{enabled = true},
                                                       prompts = #mcp_capability{enabled = true}},
                          options => Options,
                          legacy => true},
                    case erlmcp_registry:register_server(default_stdio_server,
                                                         ServerPid,
                                                         ServerConfig)
                    of
                        ok ->
                            {ok, ServerPid};
                        {error, already_registered} ->
                            {ok, ServerPid};
                        {error, Reason} ->
                            logger:warning("Legacy server started but registration failed: ~p",
                                           [Reason]),
                            {ok, ServerPid}
                    end
            end;
        Error ->
            Error
    end.

-spec stop_legacy_stdio_server() -> ok.
stop_legacy_stdio_server() ->
    case whereis(erlmcp_stdio_server) of
        undefined ->
            ok;
        _Pid ->
            erlmcp_stdio_server:stop(),
            ok
    end.
