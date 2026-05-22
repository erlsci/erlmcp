-module(erlmcp_registry).

-behaviour(gen_server).

-include("erlmcp.hrl").

%% Private records (relocated from include/erlmcp.hrl in M1-3)
-record(mcp_capability, {enabled = false :: boolean()}).
-record(mcp_server_capabilities, {
    resources :: #mcp_capability{} | undefined,
    tools :: #mcp_capability{} | undefined,
    prompts :: #mcp_capability{} | undefined,
    logging :: #mcp_capability{} | undefined
}).

%% API exports
-export([start_link/0, register_server/3, register_transport/3, unregister_server/1,
         unregister_transport/1, find_server/1,
         find_transport/1, list_servers/0, list_transports/0, bind_transport_to_server/2,
         unbind_transport/1, get_server_for_transport/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

%% Types
-type server_id() :: atom() | binary().
-type transport_id() :: atom() | binary().
-type server_config() ::
    #{capabilities => #mcp_server_capabilities{},
      options => map(),
      _ => _}.
-type transport_config() ::
    #{type => stdio | tcp | http,
      server_id => server_id(),
      config => map(),
      _ => _}.

-export_type([server_id/0, transport_id/0]).

%% State record
-record(registry_state,
        {servers = #{} :: #{server_id() => {pid(), server_config()}},
         transports = #{} :: #{transport_id() => {pid(), transport_config()}},
         server_transport_map = #{} :: #{transport_id() => server_id()},
         capabilities = #{} :: #{server_id() => #mcp_server_capabilities{}},
         monitors = #{} :: #{pid() => {server_id() | transport_id(), server | transport}},
         monitor_refs = #{} :: #{pid() => reference()}}).  % Track monitor references

-type state() :: #registry_state{}.

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec register_server(server_id(), pid(), server_config()) -> ok | {error, term()}.
register_server(ServerId, ServerPid, Config) when is_pid(ServerPid) ->
    gen_server:call(?MODULE, {register_server, ServerId, ServerPid, Config}).

-spec register_transport(transport_id(), pid(), transport_config()) ->
                            ok | {error, term()}.
register_transport(TransportId, TransportPid, Config) when is_pid(TransportPid) ->
    gen_server:call(?MODULE, {register_transport, TransportId, TransportPid, Config}).

-spec unregister_server(server_id()) -> ok.
unregister_server(ServerId) ->
    gen_server:call(?MODULE, {unregister_server, ServerId}).

-spec unregister_transport(transport_id()) -> ok.
unregister_transport(TransportId) ->
    gen_server:call(?MODULE, {unregister_transport, TransportId}).

-spec find_server(server_id()) -> {ok, {pid(), server_config()}} | {error, not_found}.
find_server(ServerId) ->
    gen_server:call(?MODULE, {find_server, ServerId}).

-spec find_transport(transport_id()) ->
                        {ok, {pid(), transport_config()}} | {error, not_found}.
find_transport(TransportId) ->
    gen_server:call(?MODULE, {find_transport, TransportId}).

-spec list_servers() -> [{server_id(), {pid(), server_config()}}].
list_servers() ->
    gen_server:call(?MODULE, list_servers).

-spec list_transports() -> [{transport_id(), {pid(), transport_config()}}].
list_transports() ->
    gen_server:call(?MODULE, list_transports).

-spec bind_transport_to_server(transport_id(), server_id()) -> ok | {error, term()}.
bind_transport_to_server(TransportId, ServerId) ->
    gen_server:call(?MODULE, {bind_transport_to_server, TransportId, ServerId}).

-spec unbind_transport(transport_id()) -> ok.
unbind_transport(TransportId) ->
    gen_server:call(?MODULE, {unbind_transport, TransportId}).

-spec get_server_for_transport(transport_id()) -> {ok, server_id()} | {error, not_found}.
get_server_for_transport(TransportId) ->
    gen_server:call(?MODULE, {get_server_for_transport, TransportId}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init([]) -> {ok, state()}.
init([]) ->
    process_flag(trap_exit, true),
    logger:info("Starting MCP registry"),
    {ok, #registry_state{}}.

-spec handle_call(term(), {pid(), term()}, state()) -> {reply, term(), state()}.
handle_call({register_server, ServerId, ServerPid, Config}, _From, State) ->
    case maps:get(ServerId, State#registry_state.servers, undefined) of
        undefined ->
            MonitorRef = monitor(process, ServerPid),
            Capabilities = maps:get(capabilities, Config, undefined),

            NewServers = maps:put(ServerId, {ServerPid, Config}, State#registry_state.servers),
            NewCapabilities =
                case Capabilities of
                    undefined ->
                        State#registry_state.capabilities;
                    _ ->
                        maps:put(ServerId, Capabilities, State#registry_state.capabilities)
                end,
            NewMonitors = maps:put(ServerPid, {ServerId, server}, State#registry_state.monitors),
            NewMonitorRefs = maps:put(ServerPid, MonitorRef, State#registry_state.monitor_refs),

            NewState =
                State#registry_state{servers = NewServers,
                                     capabilities = NewCapabilities,
                                     monitors = NewMonitors,
                                     monitor_refs = NewMonitorRefs},

            logger:info("Registered server ~p with pid ~p", [ServerId, ServerPid]),
            {reply, ok, NewState};
        {ExistingPid, _} ->
            logger:warning("Server ~p already registered with pid ~p", [ServerId, ExistingPid]),
            {reply, {error, already_registered}, State}
    end;
handle_call({register_transport, TransportId, TransportPid, Config}, _From, State) ->
    case maps:get(TransportId, State#registry_state.transports, undefined) of
        undefined ->
            MonitorRef = monitor(process, TransportPid),

            NewTransports =
                maps:put(TransportId, {TransportPid, Config}, State#registry_state.transports),
            NewMonitors =
                maps:put(TransportPid, {TransportId, transport}, State#registry_state.monitors),
            NewMonitorRefs = maps:put(TransportPid, MonitorRef, State#registry_state.monitor_refs),

            NewState =
                State#registry_state{transports = NewTransports,
                                     monitors = NewMonitors,
                                     monitor_refs = NewMonitorRefs},

            % Auto-bind to server if specified in config
            FinalState =
                case maps:get(server_id, Config, undefined) of
                    undefined ->
                        NewState;
                    ServerId ->
                        NewMap =
                            maps:put(TransportId,
                                     ServerId,
                                     NewState#registry_state.server_transport_map),
                        NewState#registry_state{server_transport_map = NewMap}
                end,

            logger:info("Registered transport ~p with pid ~p", [TransportId, TransportPid]),
            {reply, ok, FinalState};
        {ExistingPid, _} ->
            logger:warning("Transport ~p already registered with pid ~p",
                           [TransportId, ExistingPid]),
            {reply, {error, already_registered}, State}
    end;
handle_call({unregister_server, ServerId}, _From, State) ->
    case maps:take(ServerId, State#registry_state.servers) of
        {{ServerPid, _Config}, NewServers} ->
            % Demonitor the process
            case maps:get(ServerPid, State#registry_state.monitor_refs, undefined) of
                undefined ->
                    ok;
                MonitorRef ->
                    demonitor(MonitorRef, [flush])
            end,

            % Remove from monitors
            NewMonitors = maps:remove(ServerPid, State#registry_state.monitors),
            NewMonitorRefs = maps:remove(ServerPid, State#registry_state.monitor_refs),
            % Remove capabilities
            NewCapabilities = maps:remove(ServerId, State#registry_state.capabilities),
            % Remove any transport bindings
            NewTransportMap =
                maps:filter(fun(_, SId) -> SId =/= ServerId end,
                            State#registry_state.server_transport_map),

            NewState =
                State#registry_state{servers = NewServers,
                                     capabilities = NewCapabilities,
                                     server_transport_map = NewTransportMap,
                                     monitors = NewMonitors,
                                     monitor_refs = NewMonitorRefs},

            logger:info("Unregistered server ~p", [ServerId]),
            {reply, ok, NewState};
        error ->
            {reply, ok, State}  % Already unregistered
    end;
handle_call({unregister_transport, TransportId}, _From, State) ->
    case maps:take(TransportId, State#registry_state.transports) of
        {{TransportPid, _Config}, NewTransports} ->
            % Demonitor the process
            case maps:get(TransportPid, State#registry_state.monitor_refs, undefined) of
                undefined ->
                    ok;
                MonitorRef ->
                    demonitor(MonitorRef, [flush])
            end,

            % Remove from monitors
            NewMonitors = maps:remove(TransportPid, State#registry_state.monitors),
            NewMonitorRefs = maps:remove(TransportPid, State#registry_state.monitor_refs),
            % Remove binding
            NewTransportMap = maps:remove(TransportId, State#registry_state.server_transport_map),

            NewState =
                State#registry_state{transports = NewTransports,
                                     server_transport_map = NewTransportMap,
                                     monitors = NewMonitors,
                                     monitor_refs = NewMonitorRefs},

            logger:info("Unregistered transport ~p", [TransportId]),
            {reply, ok, NewState};
        error ->
            {reply, ok, State}  % Already unregistered
    end;
handle_call({find_server, ServerId}, _From, State) ->
    case maps:get(ServerId, State#registry_state.servers, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        ServerData ->
            {reply, {ok, ServerData}, State}
    end;
handle_call({find_transport, TransportId}, _From, State) ->
    case maps:get(TransportId, State#registry_state.transports, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        TransportData ->
            {reply, {ok, TransportData}, State}
    end;
handle_call(list_servers, _From, State) ->
    {reply, maps:to_list(State#registry_state.servers), State};
handle_call(list_transports, _From, State) ->
    {reply, maps:to_list(State#registry_state.transports), State};
handle_call({bind_transport_to_server, TransportId, ServerId}, _From, State) ->
    % Verify both exist
    ServerExists = maps:is_key(ServerId, State#registry_state.servers),
    TransportExists = maps:is_key(TransportId, State#registry_state.transports),

    case {ServerExists, TransportExists} of
        {true, true} ->
            NewMap = maps:put(TransportId, ServerId, State#registry_state.server_transport_map),
            NewState = State#registry_state{server_transport_map = NewMap},
            logger:info("Bound transport ~p to server ~p", [TransportId, ServerId]),
            {reply, ok, NewState};
        {false, _} ->
            {reply, {error, server_not_found}, State};
        {_, false} ->
            {reply, {error, transport_not_found}, State}
    end;
handle_call({unbind_transport, TransportId}, _From, State) ->
    NewMap = maps:remove(TransportId, State#registry_state.server_transport_map),
    NewState = State#registry_state{server_transport_map = NewMap},
    {reply, ok, NewState};
handle_call({get_server_for_transport, TransportId}, _From, State) ->
    case maps:get(TransportId, State#registry_state.server_transport_map, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        ServerId ->
            {reply, {ok, ServerId}, State}
    end;
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info({'DOWN', MonitorRef, process, Pid, Reason}, State) ->
    case maps:get(Pid, State#registry_state.monitors, undefined) of
        {Id, server} ->
            logger:warning("Server ~p (pid ~p) died: ~p", [Id, Pid, Reason]),
            NewState = cleanup_server(Id, Pid, State),
            {noreply, NewState};
        {Id, transport} ->
            logger:warning("Transport ~p (pid ~p) died: ~p", [Id, Pid, Reason]),
            NewState = cleanup_transport(Id, Pid, State),
            {noreply, NewState};
        undefined ->
            % Try to demonitor in case it's a stale reference
            catch demonitor(MonitorRef, [flush]),
            logger:warning("Unknown monitored process ~p died: ~p", [Pid, Reason]),
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    % Clean up all monitors
    maps:foreach(fun(_Pid, MonitorRef) -> catch demonitor(MonitorRef, [flush]) end,
                 State#registry_state.monitor_refs),
    logger:info("MCP registry terminating"),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec cleanup_server(server_id(), pid(), state()) -> state().
cleanup_server(ServerId, ServerPid, State) ->
    % Demonitor if we have a reference
    case maps:get(ServerPid, State#registry_state.monitor_refs, undefined) of
        undefined ->
            ok;
        MonitorRef ->
            catch demonitor(MonitorRef, [flush])
    end,

    NewServers = maps:remove(ServerId, State#registry_state.servers),
    NewCapabilities = maps:remove(ServerId, State#registry_state.capabilities),
    NewMonitors = maps:remove(ServerPid, State#registry_state.monitors),
    NewMonitorRefs = maps:remove(ServerPid, State#registry_state.monitor_refs),

    % Remove any transport bindings
    NewTransportMap =
        maps:filter(fun(_, SId) -> SId =/= ServerId end,
                    State#registry_state.server_transport_map),

    State#registry_state{servers = NewServers,
                         capabilities = NewCapabilities,
                         server_transport_map = NewTransportMap,
                         monitors = NewMonitors,
                         monitor_refs = NewMonitorRefs}.

-spec cleanup_transport(transport_id(), pid(), state()) -> state().
cleanup_transport(TransportId, TransportPid, State) ->
    % Demonitor if we have a reference
    case maps:get(TransportPid, State#registry_state.monitor_refs, undefined) of
        undefined ->
            ok;
        MonitorRef ->
            catch demonitor(MonitorRef, [flush])
    end,

    NewTransports = maps:remove(TransportId, State#registry_state.transports),
    NewTransportMap = maps:remove(TransportId, State#registry_state.server_transport_map),
    NewMonitors = maps:remove(TransportPid, State#registry_state.monitors),
    NewMonitorRefs = maps:remove(TransportPid, State#registry_state.monitor_refs),

    State#registry_state{transports = NewTransports,
                         server_transport_map = NewTransportMap,
                         monitors = NewMonitors,
                         monitor_refs = NewMonitorRefs}.
