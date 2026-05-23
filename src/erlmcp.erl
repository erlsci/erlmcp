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
%% Resources (M2b)
%%====================================================================

-spec add_resource(pid(), resource_spec()) -> ok.
add_resource(Session, Spec) when is_pid(Session), is_map(Spec) ->
    erlmcp_server_session:register_resource(Session, Spec).

-spec remove_resource(pid(), binary()) -> ok.
remove_resource(Session, Uri) when is_pid(Session), is_binary(Uri) ->
    erlmcp_server_session:unregister_resource(Session, Uri).

-spec add_resource_template(pid(), resource_spec()) -> ok.
add_resource_template(Session, Spec) when is_pid(Session), is_map(Spec) ->
    erlmcp_server_session:register_resource_template(Session, Spec).

-spec remove_resource_template(pid(), binary()) -> ok.
remove_resource_template(Session, UriTemplate) when is_pid(Session), is_binary(UriTemplate) ->
    erlmcp_server_session:unregister_resource_template(Session, UriTemplate).

-spec notify_resource_updated(pid(), binary()) -> ok.
notify_resource_updated(Session, Uri) when is_pid(Session), is_binary(Uri) ->
    erlmcp_server_session:notify_resource_updated(Session, Uri).

%%====================================================================
%% Prompts (M2b)
%%====================================================================

-spec add_prompt(pid(), prompt_spec()) -> ok.
add_prompt(Session, Spec) when is_pid(Session), is_map(Spec) ->
    erlmcp_server_session:register_prompt(Session, Spec).

-spec remove_prompt(pid(), binary()) -> ok.
remove_prompt(Session, Name) when is_pid(Session), is_binary(Name) ->
    erlmcp_server_session:unregister_prompt(Session, Name).

%%====================================================================
%% Logging (M2b)
%%====================================================================

-spec log_message(pid(), atom(), binary(), term()) -> ok.
log_message(Session, Level, Logger, Data) when is_pid(Session), is_atom(Level) ->
    erlmcp_server_session:emit_log(Session, Level, Logger, Data).

%%====================================================================
%% Convenience setup (M4)
%%====================================================================

-spec start_stdio_setup(atom(), map()) -> {ok, #{server := pid(), transport := pid()}}.
start_stdio_setup(ServerId, Config) ->
    {ok, Server} = start_server(ServerId, Config),
    TransId = list_to_atom(atom_to_list(ServerId) ++ "_stdio"),
    {ok, Transport} = start_transport(TransId, stdio,
        #{session => Server, test_mode => maps:get(test_mode, Config, false)}),
    {ok, #{server => Server, transport => Transport}}.

-spec start_tcp_setup(atom(), map(), map()) ->
    {ok, #{server := pid(), transport := pid()}}.
start_tcp_setup(ServerId, ServerConfig, TcpConfig) ->
    {ok, Server} = start_server(ServerId, ServerConfig),
    TransId = list_to_atom(atom_to_list(ServerId) ++ "_tcp"),
    {ok, Transport} = erlmcp_transport_tcp:start_link(
        TcpConfig#{owner => Server}),
    {ok, #{server => Server, transport => Transport, transport_id => TransId}}.

-spec start_http_setup(atom(), map(), map()) ->
    {ok, #{server := pid(), transport := pid()}}.
start_http_setup(ServerId, ServerConfig, HttpConfig) ->
    {ok, Server} = start_server(ServerId, ServerConfig),
    TransId = list_to_atom(atom_to_list(ServerId) ++ "_http"),
    {ok, Transport} = erlmcp_transport_streamable_http:start_link(
        HttpConfig#{session => Server}),
    {ok, #{server => Server, transport => Transport, transport_id => TransId}}.

