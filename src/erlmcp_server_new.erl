-module(erlmcp_server_new).

-behaviour(gen_server).

-include("erlmcp.hrl").

%% API exports
-export([start_link/2, add_resource/3, add_resource_template/4, add_tool/3,
         add_tool_with_schema/4, add_prompt/3, add_prompt_with_args/4, notify_resource_updated/3,
         notify_resources_changed/1, stop/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

%% Types
-type server_id() :: atom().
-type resource_handler() :: fun((binary()) -> binary() | #mcp_content{}).
-type tool_handler() :: fun((map()) -> binary() | #mcp_content{} | [#mcp_content{}]).
-type prompt_handler() :: fun((map()) -> binary() | [map()]).

-export_type([server_id/0]).

%% State record - NO transport state
-record(state,
        {server_id :: server_id(),
         capabilities :: #mcp_server_capabilities{},
         resources = #{} :: #{binary() => {#mcp_resource{}, resource_handler()}},
         resource_templates = #{} :: #{binary() => {#mcp_resource_template{}, resource_handler()}},
         tools = #{} :: #{binary() => {#mcp_tool{}, tool_handler(), map() | undefined}},
         prompts = #{} :: #{binary() => {#mcp_prompt{}, prompt_handler()}},
         subscriptions = #{} :: #{binary() => sets:set(pid())},
         progress_tokens = #{} :: #{binary() | integer() => #mcp_progress_notification{}},
         initialized = false :: boolean()}).

-type state() :: #state{}.

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link(server_id(), map()) -> {ok, pid()} | {error, term()}.
start_link(ServerId, Config) ->
    gen_server:start_link(?MODULE, [ServerId, Config], []).

-spec add_resource(pid(), binary(), resource_handler()) -> ok.
add_resource(Server, Uri, Handler) when is_binary(Uri), is_function(Handler, 1) ->
    gen_server:call(Server, {add_resource, Uri, Handler}).

-spec add_resource_template(pid(), binary(), binary(), resource_handler()) -> ok.
add_resource_template(Server, UriTemplate, Name, Handler)
    when is_binary(UriTemplate), is_binary(Name), is_function(Handler, 1) ->
    gen_server:call(Server, {add_resource_template, UriTemplate, Name, Handler}).

-spec add_tool(pid(), binary(), tool_handler()) -> ok.
add_tool(Server, Name, Handler) when is_binary(Name), is_function(Handler, 1) ->
    gen_server:call(Server, {add_tool, Name, Handler}).

-spec add_tool_with_schema(pid(), binary(), tool_handler(), map()) -> ok.
add_tool_with_schema(Server, Name, Handler, Schema)
    when is_binary(Name), is_function(Handler, 1), is_map(Schema) ->
    gen_server:call(Server, {add_tool_with_schema, Name, Handler, Schema}).

-spec add_prompt(pid(), binary(), prompt_handler()) -> ok.
add_prompt(Server, Name, Handler) when is_binary(Name), is_function(Handler, 1) ->
    gen_server:call(Server, {add_prompt, Name, Handler}).

-spec add_prompt_with_args(pid(), binary(), prompt_handler(), [#mcp_prompt_argument{}]) ->
                              ok.
add_prompt_with_args(Server, Name, Handler, Arguments)
    when is_binary(Name), is_function(Handler, 1), is_list(Arguments) ->
    gen_server:call(Server, {add_prompt_with_args, Name, Handler, Arguments}).

-spec notify_resource_updated(pid(), binary(), map()) -> ok.
notify_resource_updated(Server, Uri, Metadata) when is_binary(Uri), is_map(Metadata) ->
    gen_server:cast(Server, {notify_resource_updated, Uri, Metadata}).

-spec notify_resources_changed(pid()) -> ok.
notify_resources_changed(Server) ->
    gen_server:cast(Server, notify_resources_changed).

-spec stop(pid()) -> ok.
stop(Server) ->
    gen_server:stop(Server).

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init([server_id() | map()]) -> {ok, state()}.
init([ServerId, Config]) ->
    process_flag(trap_exit, true),

    Capabilities = maps:get(capabilities, Config, #mcp_server_capabilities{}),

    State = #state{server_id = ServerId, capabilities = Capabilities},

    logger:info("Starting MCP server ~p", [ServerId]),
    {ok, State}.

-spec handle_call(term(), {pid(), term()}, state()) -> {reply, term(), state()}.
handle_call({add_resource, Uri, Handler}, _From, State) ->
    Resource =
        #mcp_resource{uri = Uri,
                      name = Uri,
                      mime_type = ?MCP_MIME_TEXT_PLAIN},
    NewResources = maps:put(Uri, {Resource, Handler}, State#state.resources),
    {reply, ok, State#state{resources = NewResources}};
handle_call({add_resource_template, UriTemplate, Name, Handler}, _From, State) ->
    Template =
        #mcp_resource_template{uri_template = UriTemplate,
                               name = Name,
                               mime_type = ?MCP_MIME_TEXT_PLAIN},
    NewTemplates = maps:put(UriTemplate, {Template, Handler}, State#state.resource_templates),
    {reply, ok, State#state{resource_templates = NewTemplates}};
handle_call({add_tool, Name, Handler}, _From, State) ->
    Tool = #mcp_tool{name = Name, description = <<"Tool: ", Name/binary>>},
    NewTools = maps:put(Name, {Tool, Handler, undefined}, State#state.tools),
    {reply, ok, State#state{tools = NewTools}};
handle_call({add_tool_with_schema, Name, Handler, Schema}, _From, State) ->
    Tool =
        #mcp_tool{name = Name,
                  description = <<"Tool: ", Name/binary>>,
                  input_schema = Schema},
    NewTools = maps:put(Name, {Tool, Handler, Schema}, State#state.tools),
    {reply, ok, State#state{tools = NewTools}};
handle_call({add_prompt, Name, Handler}, _From, State) ->
    Prompt = #mcp_prompt{name = Name},
    NewPrompts = maps:put(Name, {Prompt, Handler}, State#state.prompts),
    {reply, ok, State#state{prompts = NewPrompts}};
handle_call({add_prompt_with_args, Name, Handler, Arguments}, _From, State) ->
    Prompt = #mcp_prompt{name = Name, arguments = Arguments},
    NewPrompts = maps:put(Name, {Prompt, Handler}, State#state.prompts),
    {reply, ok, State#state{prompts = NewPrompts}};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({notify_resource_updated, Uri, Metadata}, State) ->
    % Send notification via registry to all bound transports
    Params = #{?MCP_PARAM_URI => Uri, ?MCP_PARAM_METADATA => Metadata},
    send_notification_via_registry(State,
                                   ?MCP_METHOD_NOTIFICATIONS_RESOURCES_UPDATED,
                                   Params),
    {noreply, State};
handle_cast(notify_resources_changed, State) ->
    send_notification_via_registry(State,
                                   ?MCP_METHOD_NOTIFICATIONS_RESOURCES_LIST_CHANGED,
                                   #{}),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
% Handle messages routed from registry
handle_info({mcp_message, TransportId, Data}, State) ->
    case erlmcp_json_rpc:decode_message(Data) of
        {ok,
         #json_rpc_request{id = Id,
                           method = Method,
                           params = Params}} ->
            handle_request(Id, Method, Params, TransportId, State);
        {ok, #json_rpc_notification{method = Method, params = Params}} ->
            handle_notification(Method, Params, State);
        {error, Reason} ->
            logger:error("Failed to decode message: ~p", [Reason]),
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #state{server_id = ServerId}) ->
    logger:info("MCP server ~p terminating", [ServerId]),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions - Request Handling
%%====================================================================

-spec handle_request(json_rpc_id(), binary(), json_rpc_params(), atom(), state()) ->
                        {noreply, state()}.
handle_request(Id, ?MCP_METHOD_INITIALIZE, _Params, TransportId, State) ->
    Response = build_initialize_response(State#state.capabilities),
    send_response_via_registry(State, TransportId, Id, Response),
    {noreply, State#state{initialized = true}};
handle_request(Id, ?MCP_METHOD_RESOURCES_LIST, _Params, TransportId, State) ->
    Resources = list_all_resources(State),
    send_response_via_registry(State, TransportId, Id, #{?MCP_PARAM_RESOURCES => Resources}),
    {noreply, State};
handle_request(Id, ?MCP_METHOD_RESOURCES_READ, Params, TransportId, State) ->
    case maps:get(?MCP_PARAM_URI, Params, undefined) of
        undefined ->
            send_error_via_registry(State,
                                    TransportId,
                                    Id,
                                    ?JSONRPC_INVALID_PARAMS,
                                    ?MCP_MSG_MISSING_URI_PARAMETER);
        Uri ->
            handle_read_resource(Id, Uri, TransportId, State)
    end,
    {noreply, State};
handle_request(Id, ?MCP_METHOD_TOOLS_LIST, _Params, TransportId, State) ->
    Tools = list_all_tools(State),
    send_response_via_registry(State, TransportId, Id, #{?MCP_PARAM_TOOLS => Tools}),
    {noreply, State};
handle_request(Id, ?MCP_METHOD_TOOLS_CALL, Params, TransportId, State) ->
    Name = maps:get(?MCP_PARAM_NAME, Params, undefined),
    Args = maps:get(?MCP_PARAM_ARGUMENTS, Params, #{}),
    case {Name, Args} of
        {undefined, _} ->
            send_error_via_registry(State,
                                    TransportId,
                                    Id,
                                    ?JSONRPC_INVALID_PARAMS,
                                    ?MCP_MSG_MISSING_TOOL_NAME);
        {ToolName, Arguments} ->
            handle_tool_call(Id, ToolName, Arguments, TransportId, State)
    end,
    {noreply, State};
handle_request(Id, ?MCP_METHOD_PROMPTS_LIST, _Params, TransportId, State) ->
    Prompts = list_all_prompts(State),
    send_response_via_registry(State, TransportId, Id, #{?MCP_PARAM_PROMPTS => Prompts}),
    {noreply, State};
handle_request(Id, ?MCP_METHOD_PROMPTS_GET, Params, TransportId, State) ->
    case maps:get(?MCP_PARAM_NAME, Params, undefined) of
        undefined ->
            send_error_via_registry(State,
                                    TransportId,
                                    Id,
                                    ?JSONRPC_INVALID_PARAMS,
                                    ?MCP_MSG_MISSING_PROMPT_NAME);
        Name ->
            Arguments = maps:get(?MCP_PARAM_ARGUMENTS, Params, #{}),
            handle_get_prompt(Id, Name, Arguments, TransportId, State)
    end,
    {noreply, State};
handle_request(Id, _Method, _Params, TransportId, State) ->
    send_error_via_registry(State,
                            TransportId,
                            Id,
                            ?JSONRPC_METHOD_NOT_FOUND,
                            ?JSONRPC_MSG_METHOD_NOT_FOUND),
    {noreply, State}.

-spec handle_notification(binary(), map(), state()) -> {noreply, state()}.
handle_notification(_Method, _Params, State) ->
    {noreply, State}.

%%====================================================================
%% Internal functions - Registry Communication
%%====================================================================

-spec send_response_via_registry(state(), atom(), json_rpc_id(), map()) -> ok.
send_response_via_registry(#state{server_id = ServerId}, TransportId, Id, Result) ->
    Json = erlmcp_json_rpc:encode_response(Id, Result),
    erlmcp_registry:route_to_transport(TransportId, ServerId, Json).

-spec send_error_via_registry(state(), atom(), json_rpc_id(), integer(), binary()) -> ok.
send_error_via_registry(#state{server_id = ServerId}, TransportId, Id, Code, Message) ->
    Json = erlmcp_json_rpc:encode_error_response(Id, Code, Message),
    erlmcp_registry:route_to_transport(TransportId, ServerId, Json).

-spec send_notification_via_registry(state(), binary(), map()) -> ok.
send_notification_via_registry(#state{server_id = ServerId}, Method, Params) ->
    Json = erlmcp_json_rpc:encode_notification(Method, Params),
    % Send to all transports bound to this server - registry will handle routing
    % For now, we'll use a placeholder transport ID or enhance registry to support broadcast
    erlmcp_registry:route_to_transport(broadcast, ServerId, Json).

%%====================================================================
%% Internal functions - Response Building (same as original)
%%====================================================================

-spec build_initialize_response(#mcp_server_capabilities{}) -> map().
build_initialize_response(Capabilities) ->
    {ok, Version} = application:get_key(list_to_atom(binary_to_list(?APP_NAME)), vsn),
    #{?MCP_FIELD_PROTOCOL_VERSION => ?MCP_VERSION,
      ?MCP_FIELD_CAPABILITIES => encode_server_capabilities(Capabilities),
      ?MCP_FIELD_SERVER_INFO =>
          #{?MCP_INFO_NAME => ?APP_NAME, ?MCP_INFO_VERSION => list_to_binary(Version)}}.

-spec encode_server_capabilities(#mcp_server_capabilities{}) -> map().
encode_server_capabilities(#mcp_server_capabilities{} = Caps) ->
    Base = #{},
    Base1 =
        maybe_add_server_capability(Base,
                                    ?MCP_CAPABILITY_RESOURCES,
                                    Caps#mcp_server_capabilities.resources,
                                    #{?MCP_FEATURE_SUBSCRIBE => true,
                                      ?MCP_FEATURE_LIST_CHANGED => true}),
    Base2 =
        maybe_add_server_capability(Base1,
                                    ?MCP_CAPABILITY_TOOLS,
                                    Caps#mcp_server_capabilities.tools,
                                    #{}),
    Base3 =
        maybe_add_server_capability(Base2,
                                    ?MCP_CAPABILITY_PROMPTS,
                                    Caps#mcp_server_capabilities.prompts,
                                    #{?MCP_FEATURE_LIST_CHANGED => true}),
    maybe_add_server_capability(Base3,
                                ?MCP_CAPABILITY_LOGGING,
                                Caps#mcp_server_capabilities.logging,
                                #{}).

-spec maybe_add_server_capability(map(),
                                  binary(),
                                  #mcp_capability{} | undefined,
                                  map()) ->
                                     map().
maybe_add_server_capability(Map, _Key, undefined, _Value) ->
    Map;
maybe_add_server_capability(Map, Key, #mcp_capability{enabled = true}, Value) ->
    Map#{Key => Value};
maybe_add_server_capability(Map, _Key, _, _Value) ->
    Map.

-spec list_all_resources(state()) -> [map()].
list_all_resources(State) ->
    maps:fold(fun(_Uri, {Resource, _Handler}, Acc) -> [encode_resource(Resource) | Acc] end,
              [],
              State#state.resources).

-spec list_all_tools(state()) -> [map()].
list_all_tools(State) ->
    maps:fold(fun(_Name, {Tool, _Handler, _Schema}, Acc) -> [encode_tool(Tool) | Acc] end,
              [],
              State#state.tools).

-spec list_all_prompts(state()) -> [map()].
list_all_prompts(State) ->
    maps:fold(fun(_Name, {Prompt, _Handler}, Acc) -> [encode_prompt(Prompt) | Acc] end,
              [],
              State#state.prompts).

-spec encode_resource(#mcp_resource{}) -> map().
encode_resource(#mcp_resource{} = Resource) ->
    Base =
        #{?MCP_PARAM_URI => Resource#mcp_resource.uri,
          ?MCP_PARAM_NAME => Resource#mcp_resource.name},
    Base1 = maybe_add_field(Base, ?MCP_PARAM_DESCRIPTION, Resource#mcp_resource.description),
    Base2 = maybe_add_field(Base1, ?MCP_PARAM_MIME_TYPE, Resource#mcp_resource.mime_type),
    maybe_add_field(Base2, ?MCP_PARAM_METADATA, Resource#mcp_resource.metadata).

-spec encode_tool(#mcp_tool{}) -> map().
encode_tool(#mcp_tool{} = Tool) ->
    Base =
        #{?MCP_PARAM_NAME => Tool#mcp_tool.name,
          ?MCP_PARAM_DESCRIPTION => Tool#mcp_tool.description},
    maybe_add_field(Base, ?MCP_PARAM_INPUT_SCHEMA, Tool#mcp_tool.input_schema).

-spec encode_prompt(#mcp_prompt{}) -> map().
encode_prompt(#mcp_prompt{} = Prompt) ->
    Base = #{?MCP_PARAM_NAME => Prompt#mcp_prompt.name},
    Base1 = maybe_add_field(Base, ?MCP_PARAM_DESCRIPTION, Prompt#mcp_prompt.description),
    case Prompt#mcp_prompt.arguments of
        undefined ->
            Base1;
        Args ->
            Base1#{?MCP_PARAM_ARGUMENTS => [encode_prompt_argument(Arg) || Arg <- Args]}
    end.

-spec encode_prompt_argument(#mcp_prompt_argument{}) -> map().
encode_prompt_argument(#mcp_prompt_argument{} = Arg) ->
    Base =
        #{?MCP_PARAM_NAME => Arg#mcp_prompt_argument.name,
          ?MCP_PARAM_REQUIRED => Arg#mcp_prompt_argument.required},
    maybe_add_field(Base, ?MCP_PARAM_DESCRIPTION, Arg#mcp_prompt_argument.description).

-spec maybe_add_field(map(), binary(), term()) -> map().
maybe_add_field(Map, _Key, undefined) ->
    Map;
maybe_add_field(Map, Key, Value) ->
    Map#{Key => Value}.

%%====================================================================
%% Internal functions - Resource & Tool Handling (abbreviated for brevity)
%%====================================================================

-spec handle_read_resource(json_rpc_id(), binary(), atom(), state()) -> ok.
handle_read_resource(Id, Uri, TransportId, State) ->
    case maps:get(Uri, State#state.resources, undefined) of
        undefined ->
            send_error_via_registry(State,
                                    TransportId,
                                    Id,
                                    ?MCP_ERROR_RESOURCE_NOT_FOUND,
                                    ?MCP_MSG_RESOURCE_NOT_FOUND);
        {Resource, Handler} ->
            try
                Content = Handler(Uri),
                ContentItem = encode_content_item(Content, Resource, Uri),
                send_response_via_registry(State,
                                           TransportId,
                                           Id,
                                           #{?MCP_PARAM_CONTENTS => [ContentItem]})
            catch
                Class:Reason:Stack ->
                    logger:error("Resource handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
                    send_error_via_registry(State,
                                            TransportId,
                                            Id,
                                            ?JSONRPC_INTERNAL_ERROR,
                                            ?JSONRPC_MSG_INTERNAL_ERROR)
            end
    end.

-spec handle_tool_call(json_rpc_id(), binary(), map(), atom(), state()) -> ok.
handle_tool_call(Id, Name, Arguments, TransportId, State) ->
    case maps:get(Name, State#state.tools, undefined) of
        undefined ->
            send_error_via_registry(State,
                                    TransportId,
                                    Id,
                                    ?MCP_ERROR_TOOL_NOT_FOUND,
                                    ?MCP_MSG_TOOL_NOT_FOUND);
        {_Tool, Handler, _Schema} ->
            try
                Result = Handler(Arguments),
                ContentList = normalize_tool_result(Result),
                send_response_via_registry(State,
                                           TransportId,
                                           Id,
                                           #{?MCP_PARAM_CONTENT => ContentList})
            catch
                Class:Reason:Stack ->
                    logger:error("Tool handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
                    send_error_via_registry(State,
                                            TransportId,
                                            Id,
                                            ?JSONRPC_INTERNAL_ERROR,
                                            ?JSONRPC_MSG_INTERNAL_ERROR)
            end
    end.

-spec handle_get_prompt(json_rpc_id(), binary(), map(), atom(), state()) -> ok.
handle_get_prompt(Id, Name, Arguments, TransportId, State) ->
    case maps:get(Name, State#state.prompts, undefined) of
        undefined ->
            send_error_via_registry(State,
                                    TransportId,
                                    Id,
                                    ?MCP_ERROR_PROMPT_NOT_FOUND,
                                    ?MCP_MSG_PROMPT_NOT_FOUND);
        {Prompt, Handler} ->
            try
                Result = Handler(Arguments),
                Messages = normalize_prompt_result(Result),
                Response = #{?MCP_PARAM_MESSAGES => Messages},
                Response1 =
                    maybe_add_field(Response,
                                    ?MCP_PARAM_DESCRIPTION,
                                    Prompt#mcp_prompt.description),
                send_response_via_registry(State, TransportId, Id, Response1)
            catch
                Class:Reason:Stack ->
                    logger:error("Prompt handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
                    send_error_via_registry(State,
                                            TransportId,
                                            Id,
                                            ?JSONRPC_INTERNAL_ERROR,
                                            ?JSONRPC_MSG_INTERNAL_ERROR)
            end
    end.

%% Helper functions (simplified versions)
-spec encode_content_item(binary() | #mcp_content{}, #mcp_resource{}, binary()) -> map().
encode_content_item(BinaryContent, _Resource, Uri) when is_binary(BinaryContent) ->
    #{?MCP_PARAM_URI => Uri,
      ?MCP_PARAM_MIME_TYPE => ?MCP_MIME_TEXT_PLAIN,
      ?MCP_PARAM_TEXT => BinaryContent}.

-spec normalize_tool_result(term()) -> [map()].
normalize_tool_result(BinaryResult) when is_binary(BinaryResult) ->
    [#{?MCP_PARAM_TYPE => ?MCP_CONTENT_TYPE_TEXT, ?MCP_PARAM_TEXT => BinaryResult}].

-spec normalize_prompt_result(term()) -> [map()].
normalize_prompt_result(BinaryResult) when is_binary(BinaryResult) ->
    [#{?MCP_PARAM_ROLE => ?MCP_ROLE_USER,
       ?MCP_PARAM_CONTENT =>
           #{?MCP_PARAM_TYPE => ?MCP_CONTENT_TYPE_TEXT, ?MCP_PARAM_TEXT => BinaryResult}}];
normalize_prompt_result(MessageList) when is_list(MessageList) ->
    MessageList.
