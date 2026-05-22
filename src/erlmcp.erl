-module(erlmcp).

%% Public facade — redesigned in M2. Currently minimal stubs
%% for compilation; the legacy API was removed with the legacy
%% server modules in M1-15.

%% Application management API
-export([start_server/1, start_server/2, stop_server/1, list_servers/0,
         start_transport/2, start_transport/3, stop_transport/1,
         list_transports/0, bind_transport_to_server/2, unbind_transport/1]).
%% Tool API (M2a)
-export([add_tool/2, remove_tool/2, register_handler/2]).
%% Content constructors (M2a)
-export([text/1, image/2, audio/2, embedded_resource/1, resource_link/2]).
%% Discoverability (M2a)
-export([make_directory_tool/0, conformance_tools/1]).
%% Server operations API (M2b stubs)
-export([add_resource/3, add_resource/4, add_prompt/3, add_prompt/4]).

%% Types
-type server_id() :: atom().
-type transport_id() :: atom().
-type transport_type() :: stdio | tcp | http.

-type tool_spec() :: map().
-type tool_result() :: {ok, [content()]} | {ok, content()} | {error, integer(), binary()}.
-type content() :: map().
-type ctx() :: erlmcp_ctx:ctx().

-export_type([server_id/0, transport_id/0, transport_type/0,
              tool_spec/0, tool_result/0, content/0, ctx/0]).

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
%% Tool API (M2a)
%%====================================================================

-spec add_tool(pid(), tool_spec()) -> ok | {error, term()}.
add_tool(Session, ToolSpec) when is_pid(Session), is_map(ToolSpec) ->
    erlmcp_server_session:register_tool(Session, ToolSpec).

-spec remove_tool(pid(), binary()) -> ok.
remove_tool(Session, ToolName) when is_pid(Session), is_binary(ToolName) ->
    erlmcp_server_session:unregister_tool(Session, ToolName).

-spec register_handler(pid(), module()) -> ok.
register_handler(Session, Module) when is_pid(Session), is_atom(Module) ->
    erlmcp_server_session:register_handler(Session, Module).

%%====================================================================
%% Content constructors (M2a)
%%====================================================================

-spec text(binary()) -> content().
text(Text) when is_binary(Text) ->
    #{<<"type">> => <<"text">>, <<"text">> => Text}.

-spec image(binary(), binary()) -> content().
image(Data, MimeType) when is_binary(Data), is_binary(MimeType) ->
    #{<<"type">> => <<"image">>, <<"data">> => Data, <<"mimeType">> => MimeType}.

-spec audio(binary(), binary()) -> content().
audio(Data, MimeType) when is_binary(Data), is_binary(MimeType) ->
    #{<<"type">> => <<"audio">>, <<"data">> => Data, <<"mimeType">> => MimeType}.

-spec embedded_resource(map()) -> content().
embedded_resource(Resource) when is_map(Resource) ->
    #{<<"type">> => <<"resource">>, <<"resource">> => Resource}.

-spec resource_link(binary(), binary()) -> content().
resource_link(Uri, MimeType) when is_binary(Uri), is_binary(MimeType) ->
    #{<<"type">> => <<"resource_link">>, <<"uri">> => Uri, <<"mimeType">> => MimeType}.

%%====================================================================
%% Discoverability (M2a)
%%====================================================================

-spec make_directory_tool() -> tool_spec().
make_directory_tool() ->
    #{
        name => <<"directory">>,
        description => <<"Returns a categorized listing of all available tools">>,
        input_schema => erlmcp_schema:object([]),
        category => <<"meta">>,
        when_to_use => <<"When you need an overview of all available tools">>,
        is_directory => true,
        handler => fun directory_handler/2
    }.

-spec conformance_tools(pid()) -> [tool_spec()].
conformance_tools(Session) ->
    AllTools = erlmcp_server_session:list_tools(Session),
    [T || T <- AllTools, maps:get(is_directory, T, false) =/= true].

directory_handler(_Args, Ctx) ->
    Session = erlmcp_ctx:session(Ctx),
    AllTools = erlmcp_server_session:list_tools(Session),
    Tools = [T || T <- AllTools, maps:get(is_directory, T, false) =/= true],
    Categorized = group_by_category(Tools),
    Entries = maps:fold(fun(Cat, CatTools, Acc) ->
        ToolEntries = [#{
            <<"name">> => maps:get(name, T),
            <<"description">> => maps:get(description, T, <<>>),
            <<"when_to_use">> => maps:get(when_to_use, T, <<>>),
            <<"next">> => maps:get(next, T, [])
        } || T <- CatTools],
        Acc#{Cat => ToolEntries}
    end, #{}, Categorized),
    {ok, Payload} = erlmcp_codec:encode(Entries),
    {ok, text(Payload)}.

group_by_category(Tools) ->
    lists:foldl(fun(T, Acc) ->
        Cat = maps:get(category, T, <<"uncategorized">>),
        Existing = maps:get(Cat, Acc, []),
        Acc#{Cat => Existing ++ [T]}
    end, #{}, Tools).

%%====================================================================
%% Server operations — stubs for M2b
%%====================================================================

-spec add_resource(server_id(), binary(), fun()) -> ok | {error, term()}.
add_resource(_ServerId, _Uri, _Handler) ->
    {error, not_implemented}.

-spec add_resource(server_id(), binary(), binary(), fun()) -> ok | {error, term()}.
add_resource(_ServerId, _Uri, _Name, _Handler) ->
    {error, not_implemented}.

-spec add_prompt(server_id(), binary(), fun()) -> ok | {error, term()}.
add_prompt(_ServerId, _Name, _Handler) ->
    {error, not_implemented}.

-spec add_prompt(server_id(), binary(), fun(), [map()]) -> ok | {error, term()}.
add_prompt(_ServerId, _Name, _Handler, _Args) ->
    {error, not_implemented}.

