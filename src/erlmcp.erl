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
%% Resources (M2b)
-export([add_resource/2, remove_resource/2,
         add_resource_template/2, remove_resource_template/2,
         notify_resource_updated/2]).
%% Prompts (M2b)
-export([add_prompt/2, remove_prompt/2]).
%% Logging (M2b)
-export([log_message/4]).
%% Convenience setup (M4)
-export([start_stdio_setup/2, start_tcp_setup/3, start_http_setup/3]).

%% Types
-type server_id() :: atom().
-type transport_id() :: atom().
-type transport_type() :: stdio | tcp | http.

-type tool_spec() :: map().
-type tool_result() :: {ok, [content()]} | {ok, content()} | {error, integer(), binary()}.
-type content() :: map().
-type ctx() :: erlmcp_ctx:ctx().
-type resource_spec() :: map().
-type prompt_spec() :: map().

-export_type([server_id/0, transport_id/0, transport_type/0,
              tool_spec/0, tool_result/0, content/0, ctx/0,
              resource_spec/0, prompt_spec/0]).

%%====================================================================
%% Server management
%%====================================================================

-spec start_server(server_id()) -> {ok, erlmcp_server:server()} | {error, term()} | ignore.
start_server(ServerId) ->
    start_server(ServerId, #{}).

-spec start_server(server_id(), map()) -> {ok, erlmcp_server:server()} | {error, term()} | ignore.
start_server(ServerId, Config) ->
    Opts = Config#{name => atom_to_binary(ServerId, utf8)},
    erlmcp_server:start_link(Opts).

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
    gen_server:start_ret() | {error, term()}.
start_transport(TransportId, Type) ->
    start_transport(TransportId, Type, #{}).

-spec start_transport(transport_id(), transport_type(), map()) ->
    gen_server:start_ret() | {error, term()}.
start_transport(_TransportId, stdio, Config) ->
    erlmcp_transport_stdio:start_link(Config);
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

-spec add_tool(erlmcp_server:server(), tool_spec()) -> ok | {error, term()}.
add_tool(Server, ToolSpec) when is_map(ToolSpec) ->
    erlmcp_server:register_tool(Server, ToolSpec).

-spec remove_tool(erlmcp_server:server(), binary()) -> ok.
remove_tool(Server, ToolName) when is_binary(ToolName) ->
    erlmcp_server:unregister_tool(Server, ToolName).

-spec register_handler(erlmcp_server:server(), module()) -> ok.
register_handler(Server, Module) when is_atom(Module) ->
    erlmcp_server:register_handler(Server, Module).

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
        description => <<"Start here — an oriented overview of this server, with workflow hints and which tools use advanced protocol features.">>,
        input_schema => erlmcp_schema:object([]),
        category => <<"meta">>,
        when_to_use => <<"When you need an overview of all available tools">>,
        is_directory => true,
        handler => fun directory_handler/2
    }.

-spec conformance_tools(erlmcp_server:server()) -> [tool_spec()].
conformance_tools(Server) ->
    Tab = erlmcp_server:catalog_table(Server),
    AllTools = maps:values(erlmcp_server:get_tools(Tab)),
    [T || T <- AllTools, maps:get(is_directory, T, false) =/= true].

directory_handler(_Args, Ctx) ->
    Tab = erlmcp_ctx:server_ref(Ctx),
    ServerPid = erlmcp_ctx:server_pid(Ctx),
    AllTools = case Tab of
        undefined -> [];
        _ -> maps:values(erlmcp_server:get_tools(Tab))
    end,
    Tools = [T || T <- AllTools, maps:get(is_directory, T, false) =/= true],
    Categorized = group_by_category(Tools),
    ToolEntries = maps:fold(fun(Cat, CatTools, Acc) ->
        CatEntries = [tool_directory_entry(T) || T <- CatTools],
        Acc#{Cat => CatEntries}
    end, #{}, Categorized),
    Identity = build_server_identity(ServerPid, Tab),
    Result = #{<<"server">> => Identity, <<"tools">> => ToolEntries},
    {ok, Payload} = erlmcp_codec:encode(Result),
    {ok, text(Payload)}.

tool_directory_entry(T) ->
    Base = #{
        <<"name">> => maps:get(name, T),
        <<"description">> => maps:get(description, T, <<>>),
        <<"when_to_use">> => maps:get(when_to_use, T, <<>>),
        <<"next">> => maps:get(next, T, [])
    },
    case maps:get(protocol_features, T, []) of
        [] -> Base;
        PF -> Base#{<<"protocol_features">> => [atom_to_binary(F) || F <- PF]}
    end.

build_server_identity(ServerPid, Tab) ->
    Identity = case ServerPid of
        undefined -> #{};
        _ -> erlmcp_server:get_identity(ServerPid)
    end,
    Info = erlmcp_server:get_server_info(Tab),
    Base = #{
        <<"name">> => erlmcp_model:info_name(Info),
        <<"version">> => erlmcp_model:info_version(Info)
    },
    maybe_add_field(<<"purpose">>, purpose, Identity,
    maybe_add_field(<<"source">>, source, Identity,
    maybe_add_field(<<"docs">>, docs, Identity,
    Base))).

group_by_category(Tools) ->
    Grouped = lists:foldl(fun(T, Acc) ->
        Cat = maps:get(category, T, <<"uncategorized">>),
        Existing = maps:get(Cat, Acc, []),
        Acc#{Cat => [T | Existing]}
    end, #{}, Tools),
    maps:map(fun(_, V) -> lists:reverse(V) end, Grouped).

maybe_add_field(JsonKey, ConfigKey, Config, Acc) ->
    case maps:get(ConfigKey, Config, undefined) of
        undefined -> Acc;
        V -> Acc#{JsonKey => V}
    end.

%%====================================================================
%% Resources (M2b)
%%====================================================================

-spec add_resource(erlmcp_server:server(), resource_spec()) -> ok | {error, {invalid_resource_spec, term()}}.
add_resource(Server, Spec) when is_map(Spec) ->
    erlmcp_server:register_resource(Server, Spec).

-spec remove_resource(erlmcp_server:server(), binary()) -> ok.
remove_resource(Server, Uri) when is_binary(Uri) ->
    erlmcp_server:unregister_resource(Server, Uri).

-spec add_resource_template(erlmcp_server:server(), resource_spec()) -> ok | {error, {invalid_resource_template_spec, term()}}.
add_resource_template(Server, Spec) when is_map(Spec) ->
    erlmcp_server:register_resource_template(Server, Spec).

-spec remove_resource_template(erlmcp_server:server(), binary()) -> ok.
remove_resource_template(Server, UriTemplate) when is_binary(UriTemplate) ->
    erlmcp_server:unregister_resource_template(Server, UriTemplate).

-spec notify_resource_updated(pid(), binary()) -> ok.
notify_resource_updated(Session, Uri) when is_pid(Session), is_binary(Uri) ->
    gen_statem:cast(Session, {resource_updated, Uri}).

%%====================================================================
%% Prompts (M2b)
%%====================================================================

-spec add_prompt(erlmcp_server:server(), prompt_spec()) -> ok | {error, {invalid_prompt_spec, term()}}.
add_prompt(Server, Spec) when is_map(Spec) ->
    erlmcp_server:register_prompt(Server, Spec).

-spec remove_prompt(erlmcp_server:server(), binary()) -> ok.
remove_prompt(Server, Name) when is_binary(Name) ->
    erlmcp_server:unregister_prompt(Server, Name).

%%====================================================================
%% Logging (M2b)
%%====================================================================

-spec log_message(pid(), atom(), binary(), term()) -> ok.
log_message(Session, Level, Logger, Data) when is_pid(Session), is_atom(Level) ->
    erlmcp_server_session:emit_log(Session, Level, Logger, Data).

%%====================================================================
%% Convenience setup (M4)
%%====================================================================

-spec start_stdio_setup(atom(), map()) -> {ok, pid()} | {error, term()} | ignore.
start_stdio_setup(ServerId, Config) when is_atom(ServerId) ->
    SubtreeConfig = Config#{name => atom_to_binary(ServerId, utf8)},
    case erlmcp_stdio_sup:start_link(SubtreeConfig) of
        {ok, Sup} ->
            ok = erlmcp_stdio_sup:serve(Sup),
            {ok, Sup};
        Error -> Error
    end.

-spec start_tcp_setup(atom(), map(), map()) ->
    {ok, #{server := erlmcp_server:server(), session := pid(), transport := pid(), transport_id := atom()}}.
start_tcp_setup(ServerId, ServerConfig, TcpConfig) when is_atom(ServerId) ->
    {ok, Server} = start_server(ServerId, ServerConfig),
    {ok, Session} = erlmcp_server_session:start_link(
        #{server => Server, name => atom_to_binary(ServerId, utf8)}),
    TransId = make_transport_id(ServerId, <<"_tcp">>),
    {ok, Transport} = erlmcp_transport_tcp:start_link(
        TcpConfig#{owner => Session}),
    {ok, #{server => Server, session => Session,
           transport => Transport, transport_id => TransId}}.

-spec start_http_setup(atom(), map(), map()) ->
    {ok, #{server := erlmcp_server:server(), session := pid(), transport := pid(), transport_id := atom()}}.
start_http_setup(ServerId, ServerConfig, HttpConfig) when is_atom(ServerId) ->
    {ok, Server} = start_server(ServerId, ServerConfig),
    {ok, Session} = erlmcp_server_session:start_link(
        #{server => Server, name => atom_to_binary(ServerId, utf8)}),
    TransId = make_transport_id(ServerId, <<"_http">>),
    {ok, Transport} = erlmcp_transport_streamable_http:start_link(
        HttpConfig#{session => Session}),
    {ok, #{server => Server, session => Session,
           transport => Transport, transport_id => TransId}}.

%% ServerId is a developer-supplied atom; the suffix is a fixed binary.
%% The resulting atom count is bounded by the number of servers started.
make_transport_id(ServerId, Suffix) when is_atom(ServerId), is_binary(Suffix) ->
    binary_to_atom(<<(atom_to_binary(ServerId, utf8))/binary, Suffix/binary>>, utf8).

