-module(erlmcp_server).

-behaviour(gen_server).

-include("erlmcp.hrl").

%% API exports
-export([start_link/2, add_resource/3, add_resource_template/4, add_tool/3,
         add_tool_with_schema/4, add_prompt/3, add_prompt_with_args/4, subscribe_resource/3,
         unsubscribe_resource/2, report_progress/4, notify_resource_updated/3,
         notify_resources_changed/1, stop/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

%% Types
-type server() :: pid().
-type server_id() :: atom().
-type resource_handler() :: fun((binary()) -> binary() | #mcp_content{}).
-type tool_handler() :: fun((map()) -> binary() | #mcp_content{} | [#mcp_content{}]).
-type prompt_handler() :: fun((map()) -> binary() | [map()]).

-export_type([server/0, server_id/0]).

%% State record - NO transport state, only server-specific state
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

-spec start_link(server_id(), #mcp_server_capabilities{} | map()) ->
                    {ok, server()} | {error, term()}.
start_link(ServerId, Capabilities)
    when is_record(Capabilities, mcp_server_capabilities) ->
    gen_server:start_link(?MODULE, [ServerId, Capabilities], []);
start_link(ServerId, Config) when is_map(Config) ->
    Capabilities = maps:get(capabilities, Config, #mcp_server_capabilities{}),
    gen_server:start_link(?MODULE, [ServerId, Capabilities], []).

-spec add_resource(server(), binary(), resource_handler()) -> ok.
add_resource(Server, Uri, Handler) when is_binary(Uri), is_function(Handler, 1) ->
    gen_server:call(Server, {add_resource, Uri, Handler}).

-spec add_resource_template(server(), binary(), binary(), resource_handler()) -> ok.
add_resource_template(Server, UriTemplate, Name, Handler)
    when is_binary(UriTemplate), is_binary(Name), is_function(Handler, 1) ->
    gen_server:call(Server, {add_resource_template, UriTemplate, Name, Handler}).

-spec add_tool(server(), binary(), tool_handler()) -> ok.
add_tool(Server, Name, Handler) when is_binary(Name), is_function(Handler, 1) ->
    gen_server:call(Server, {add_tool, Name, Handler}).

-spec add_tool_with_schema(server(), binary(), tool_handler(), map()) -> ok.
add_tool_with_schema(Server, Name, Handler, Schema)
    when is_binary(Name), is_function(Handler, 1), is_map(Schema) ->
    gen_server:call(Server, {add_tool_with_schema, Name, Handler, Schema}).

-spec add_prompt(server(), binary(), prompt_handler()) -> ok.
add_prompt(Server, Name, Handler) when is_binary(Name), is_function(Handler, 1) ->
    gen_server:call(Server, {add_prompt, Name, Handler}).

-spec add_prompt_with_args(server(),
                           binary(),
                           prompt_handler(),
                           [#mcp_prompt_argument{}]) ->
                              ok.
add_prompt_with_args(Server, Name, Handler, Arguments)
    when is_binary(Name), is_function(Handler, 1), is_list(Arguments) ->
    gen_server:call(Server, {add_prompt_with_args, Name, Handler, Arguments}).

-spec subscribe_resource(server(), binary(), pid()) -> ok.
subscribe_resource(Server, Uri, Subscriber) when is_binary(Uri), is_pid(Subscriber) ->
    gen_server:call(Server, {subscribe_resource, Uri, Subscriber}).

-spec unsubscribe_resource(server(), binary()) -> ok.
unsubscribe_resource(Server, Uri) when is_binary(Uri) ->
    gen_server:call(Server, {unsubscribe_resource, Uri}).

-spec report_progress(server(), binary() | integer(), float(), float()) -> ok.
report_progress(Server, Token, Progress, Total)
    when is_number(Progress), is_number(Total) ->
    gen_server:cast(Server, {report_progress, Token, Progress, Total}).

-spec notify_resource_updated(server(), binary(), map()) -> ok.
notify_resource_updated(Server, Uri, Metadata) when is_binary(Uri), is_map(Metadata) ->
    gen_server:cast(Server, {notify_resource_updated, Uri, Metadata}).

-spec notify_resources_changed(server()) -> ok.
notify_resources_changed(Server) ->
    gen_server:cast(Server, notify_resources_changed).

-spec stop(server()) -> ok.
stop(Server) ->
    gen_server:stop(Server).

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init([server_id() | #mcp_server_capabilities{}]) -> {ok, state()}.
init([ServerId, Capabilities]) ->
    process_flag(trap_exit, true),

    State = #state{server_id = ServerId, capabilities = Capabilities},

    logger:info("Starting MCP server ~p (refactored)", [ServerId]),
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
handle_call({subscribe_resource, Uri, Subscriber}, _From, State) ->
    NewSubscriptions = add_subscription(Uri, Subscriber, State#state.subscriptions),
    {reply, ok, State#state{subscriptions = NewSubscriptions}};
handle_call({unsubscribe_resource, Uri}, _From, State) ->
    NewSubscriptions = remove_subscription(Uri, State#state.subscriptions),
    {reply, ok, State#state{subscriptions = NewSubscriptions}};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({report_progress, Token, Progress, Total}, State) ->
    Notification =
        #mcp_progress_notification{progress_token = #mcp_progress_token{token = Token},
                                   progress = Progress,
                                   total = Total},
    send_progress_notification_safe(State, Token, Progress, Total),
    NewTokens = maps:put(Token, Notification, State#state.progress_tokens),
    {noreply, State#state{progress_tokens = NewTokens}};
handle_cast({notify_resource_updated, Uri, Metadata}, State) ->
    notify_subscribers(Uri, Metadata, State),
    {noreply, State};
handle_cast(notify_resources_changed, State) ->
    send_notification_safe(State, ?MCP_METHOD_NOTIFICATIONS_RESOURCES_LIST_CHANGED, #{}),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
% Handle messages routed from registry - this is the key change!
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
    logger:info("MCP server ~p (refactored) terminating", [ServerId]),
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
handle_request(Id, ?MCP_METHOD_RESOURCES_TEMPLATES_LIST, _Params, TransportId, State) ->
    Templates = list_all_templates(State),
    send_response_via_registry(State,
                               TransportId,
                               Id,
                               #{?MCP_PARAM_RESOURCE_TEMPLATES => Templates}),
    {noreply, State};
handle_request(Id, ?MCP_METHOD_RESOURCES_SUBSCRIBE, Params, TransportId, State) ->
    case maps:get(?MCP_PARAM_URI, Params, undefined) of
        undefined ->
            send_error_via_registry(State,
                                    TransportId,
                                    Id,
                                    ?JSONRPC_INVALID_PARAMS,
                                    ?MCP_MSG_MISSING_URI_PARAMETER);
        Uri ->
            NewSubscriptions = add_subscription(Uri, self(), State#state.subscriptions),
            send_response_via_registry(State, TransportId, Id, #{}),
            {noreply, State#state{subscriptions = NewSubscriptions}}
    end;
handle_request(Id, ?MCP_METHOD_RESOURCES_UNSUBSCRIBE, Params, TransportId, State) ->
    case maps:get(?MCP_PARAM_URI, Params, undefined) of
        undefined ->
            send_error_via_registry(State,
                                    TransportId,
                                    Id,
                                    ?JSONRPC_INVALID_PARAMS,
                                    ?MCP_MSG_MISSING_URI_PARAMETER);
        Uri ->
            NewSubscriptions = remove_subscription(Uri, State#state.subscriptions),
            send_response_via_registry(State, TransportId, Id, #{}),
            {noreply, State#state{subscriptions = NewSubscriptions}}
    end;
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
%% Internal functions - Registry Communication (NEW!)
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
    erlmcp_registry:route_to_transport(broadcast, ServerId, Json).

-spec send_progress_notification_via_registry(state(),
                                              binary() | integer(),
                                              float(),
                                              float()) ->
                                                 ok.
send_progress_notification_via_registry(State, Token, Progress, Total) ->
    Params =
        #{?MCP_PARAM_PROGRESS_TOKEN => Token,
          ?MCP_PARAM_PROGRESS => Progress,
          ?MCP_PARAM_TOTAL => Total},
    send_notification_via_registry(State, ?MCP_METHOD_NOTIFICATIONS_PROGRESS, Params).

%%====================================================================
%% Safe Transport Functions - Registry-based error handling
%%====================================================================

-spec send_response_safe(state(), atom(), json_rpc_id(), map()) -> ok.
send_response_safe(State, TransportId, Id, Result) ->
    try
        send_response_via_registry(State, TransportId, Id, Result)
    catch
        Class:Reason:Stack ->
            logger:warning("Failed to send response for request ~p: ~p:~p~n~p",
                           [Id, Class, Reason, Stack])
    end,
    ok.

-spec send_error_safe(state(), atom(), json_rpc_id(), integer(), binary()) -> ok.
send_error_safe(State, TransportId, Id, Code, Message) ->
    try
        send_error_via_registry(State, TransportId, Id, Code, Message)
    catch
        Class:Reason:Stack ->
            logger:warning("Failed to send error response for request ~p (code ~p): ~p:~p~n~p",
                           [Id, Code, Class, Reason, Stack])
    end,
    ok.

-spec send_notification_safe(state(), binary(), map()) -> ok.
send_notification_safe(State, Method, Params) ->
    try
        send_notification_via_registry(State, Method, Params)
    catch
        Class:Reason:Stack ->
            logger:warning("Failed to send notification ~p: ~p:~p~n~p",
                           [Method, Class, Reason, Stack])
    end,
    ok.

-spec send_progress_notification_safe(state(), binary() | integer(), float(), float()) ->
                                         ok.
send_progress_notification_safe(State, Token, Progress, Total) ->
    try
        send_progress_notification_via_registry(State, Token, Progress, Total)
    catch
        Class:Reason:Stack ->
            logger:warning("Failed to send progress notification for token ~p: ~p:~p~n~p",
                           [Token, Class, Reason, Stack])
    end,
    ok.

%%====================================================================
%% Internal functions - Response Building (same as before)
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

%%====================================================================
%% Internal functions - Resource Handling (same as before but using safe functions)
%%====================================================================

-spec list_all_resources(state()) -> [map()].
list_all_resources(State) ->
    maps:fold(fun(_Uri, {Resource, _Handler}, Acc) -> [encode_resource(Resource) | Acc] end,
              [],
              State#state.resources).

-spec list_all_templates(state()) -> [map()].
list_all_templates(State) ->
    maps:fold(fun(_UriTemplate, {Template, _Handler}, Acc) ->
                 [encode_resource_template(Template) | Acc]
              end,
              [],
              State#state.resource_templates).

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

% Resource handling functions (abbreviated for brevity - using same logic as original)
-spec handle_read_resource(json_rpc_id(), binary(), atom(), state()) -> ok.
handle_read_resource(Id, Uri, TransportId, State) ->
    case find_resource(Uri, State) of
        {ok, {Resource, Handler}} ->
            try
                Content = Handler(Uri),
                ContentItem = encode_content_item(Content, Resource, Uri),
                send_response_safe(State, TransportId, Id, #{?MCP_PARAM_CONTENTS => [ContentItem]})
            catch
                Class:Reason:Stack ->
                    logger:error("Resource handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
                    send_error_safe(State,
                                    TransportId,
                                    Id,
                                    ?JSONRPC_INTERNAL_ERROR,
                                    ?JSONRPC_MSG_INTERNAL_ERROR)
            end;
        {error, not_found} ->
            send_error_safe(State,
                            TransportId,
                            Id,
                            ?MCP_ERROR_RESOURCE_NOT_FOUND,
                            ?MCP_MSG_RESOURCE_NOT_FOUND)
    end.

-spec handle_tool_call(json_rpc_id(), binary(), map(), atom(), state()) -> ok.
handle_tool_call(Id, Name, Arguments, TransportId, State) ->
    case maps:get(Name, State#state.tools, undefined) of
        undefined ->
            send_error_safe(State,
                            TransportId,
                            Id,
                            ?MCP_ERROR_TOOL_NOT_FOUND,
                            ?MCP_MSG_TOOL_NOT_FOUND);
        {_Tool, Handler, _Schema} ->
            try
                Result = Handler(Arguments),
                ContentList = normalize_tool_result(Result),
                send_response_safe(State, TransportId, Id, #{?MCP_PARAM_CONTENT => ContentList})
            catch
                Class:Reason:Stack ->
                    logger:error("Tool handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
                    send_error_safe(State,
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
            send_error_safe(State,
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
                send_response_safe(State, TransportId, Id, Response1)
            catch
                Class:Reason:Stack ->
                    logger:error("Prompt handler crashed: ~p:~p~n~p", [Class, Reason, Stack]),
                    send_error_safe(State,
                                    TransportId,
                                    Id,
                                    ?JSONRPC_INTERNAL_ERROR,
                                    ?JSONRPC_MSG_INTERNAL_ERROR)
            end
    end.

%% Helper functions - same as original but abbreviated
-spec find_resource(binary(), state()) ->
                       {ok, {#mcp_resource{}, resource_handler()}} | {error, not_found}.
find_resource(Uri, State) ->
    case maps:get(Uri, State#state.resources, undefined) of
        undefined ->
            {error, not_found};
        Resource ->
            {ok, Resource}
    end.

-spec encode_resource(#mcp_resource{}) -> map().
encode_resource(#mcp_resource{} = Resource) ->
    #{?MCP_PARAM_URI => Resource#mcp_resource.uri,
      ?MCP_PARAM_NAME => Resource#mcp_resource.name,
      ?MCP_PARAM_MIME_TYPE => Resource#mcp_resource.mime_type}.

-spec encode_resource_template(#mcp_resource_template{}) -> map().
encode_resource_template(#mcp_resource_template{} = Template) ->
    #{?MCP_PARAM_URI_TEMPLATE => Template#mcp_resource_template.uri_template,
      ?MCP_PARAM_NAME => Template#mcp_resource_template.name,
      ?MCP_PARAM_MIME_TYPE => Template#mcp_resource_template.mime_type}.

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
    #{?MCP_PARAM_NAME => Arg#mcp_prompt_argument.name,
      ?MCP_PARAM_REQUIRED => Arg#mcp_prompt_argument.required,
      ?MCP_PARAM_DESCRIPTION => Arg#mcp_prompt_argument.description}.

-spec maybe_add_field(map(), binary(), term()) -> map().
maybe_add_field(Map, _Key, undefined) ->
    Map;
maybe_add_field(Map, Key, Value) ->
    Map#{Key => Value}.

-spec encode_content_item(binary() | #mcp_content{}, #mcp_resource{}, binary()) -> map().
encode_content_item(BinaryContent, Resource, Uri) when is_binary(BinaryContent) ->
    #{?MCP_PARAM_URI => Uri,
      ?MCP_PARAM_MIME_TYPE => Resource#mcp_resource.mime_type,
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

%%====================================================================
%% Internal functions - Subscription Handling
%%====================================================================

-spec add_subscription(binary(), pid(), map()) -> map().
add_subscription(Uri, Subscriber, Subscriptions) ->
    Subscribers = maps:get(Uri, Subscriptions, sets:new()),
    NewSubscribers = sets:add_element(Subscriber, Subscribers),
    maps:put(Uri, NewSubscribers, Subscriptions).

-spec remove_subscription(binary(), map()) -> map().
remove_subscription(Uri, Subscriptions) ->
    maps:remove(Uri, Subscriptions).

-spec notify_subscribers(binary(), map(), state()) -> ok.
notify_subscribers(Uri, Metadata, State) ->
    case maps:get(Uri, State#state.subscriptions, undefined) of
        undefined ->
            ok;
        Subscribers ->
            Params = #{?MCP_PARAM_URI => Uri, ?MCP_PARAM_METADATA => Metadata},
            sets:fold(fun(Subscriber, _) ->
                         _ = Subscriber ! {resource_updated, Uri, Metadata},
                         ok
                      end,
                      ok,
                      Subscribers),
            send_notification_safe(State, ?MCP_METHOD_NOTIFICATIONS_RESOURCES_UPDATED, Params)
    end.
