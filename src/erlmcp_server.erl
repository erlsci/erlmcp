-module(erlmcp_server).
-behaviour(gen_server).

-include("erlmcp.hrl").

%% API exports
-export([
    start_link/2,
    add_resource/3,
    add_resource_template/4,
    add_tool/3,
    add_tool_with_schema/4,
    add_prompt/3,
    add_prompt_with_args/4,
    subscribe_resource/3,
    unsubscribe_resource/2,
    report_progress/4,
    notify_resource_updated/3,
    notify_resources_changed/1,
    stop/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Types
-type server() :: pid().
-type resource_handler() :: fun((binary()) -> binary() | #mcp_content{}).
-type tool_handler() :: fun((map()) -> binary() | #mcp_content{} | [#mcp_content{}]).
-type prompt_handler() :: fun((map()) -> binary() | [map()]).

-export_type([server/0]).

%% State record
-record(state, {
    transport :: module(),
    transport_state :: term(),
    capabilities :: #mcp_server_capabilities{},
    resources = #{} :: #{binary() => {#mcp_resource{}, resource_handler()}},
    resource_templates = #{} :: #{binary() => {#mcp_resource_template{}, resource_handler()}},
    tools = #{} :: #{binary() => {#mcp_tool{}, tool_handler(), map() | undefined}},
    prompts = #{} :: #{binary() => {#mcp_prompt{}, prompt_handler()}},
    subscriptions = #{} :: #{binary() => sets:set(pid())},
    progress_tokens = #{} :: #{binary() | integer() => #mcp_progress_notification{}},
    initialized = false :: boolean()
}).

-type state() :: #state{}.

%%====================================================================
%% API Functions
%%====================================================================

-spec start_link(transport_opts(), #mcp_server_capabilities{}) -> 
    {ok, server()} | {error, term()}.
start_link(TransportOpts, Capabilities) ->
    gen_server:start_link(?MODULE, [TransportOpts, Capabilities], []).

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

-spec add_prompt_with_args(server(), binary(), prompt_handler(), [#mcp_prompt_argument{}]) -> ok.
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

-spec init([transport_opts() | #mcp_server_capabilities{}]) -> {ok, state()}.
init([TransportOpts, Capabilities]) ->
    process_flag(trap_exit, true),
    case init_transport(TransportOpts) of
        {ok, Transport, TransportState} ->
            State = #state{
                transport = Transport,
                transport_state = TransportState,
                capabilities = Capabilities
            },
            {ok, State};
        {error, Reason} ->
            {stop, Reason}
    end.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.

handle_call({add_resource, Uri, Handler}, _From, State) ->
    Resource = #mcp_resource{
        uri = Uri,
        name = Uri,
        mime_type = <<"text/plain">>
    },
    NewResources = maps:put(Uri, {Resource, Handler}, State#state.resources),
    {reply, ok, State#state{resources = NewResources}};

handle_call({add_resource_template, UriTemplate, Name, Handler}, _From, State) ->
    Template = #mcp_resource_template{
        uri_template = UriTemplate,
        name = Name,
        mime_type = <<"text/plain">>
    },
    NewTemplates = maps:put(UriTemplate, {Template, Handler}, State#state.resource_templates),
    {reply, ok, State#state{resource_templates = NewTemplates}};

handle_call({add_tool, Name, Handler}, _From, State) ->
    Tool = #mcp_tool{
        name = Name,
        description = <<"Tool: ", Name/binary>>
    },
    NewTools = maps:put(Name, {Tool, Handler, undefined}, State#state.tools),
    {reply, ok, State#state{tools = NewTools}};

handle_call({add_tool_with_schema, Name, Handler, Schema}, _From, State) ->
    Tool = #mcp_tool{
        name = Name,
        description = <<"Tool: ", Name/binary>>,
        input_schema = Schema
    },
    NewTools = maps:put(Name, {Tool, Handler, Schema}, State#state.tools),
    {reply, ok, State#state{tools = NewTools}};

handle_call({add_prompt, Name, Handler}, _From, State) ->
    Prompt = #mcp_prompt{name = Name},
    NewPrompts = maps:put(Name, {Prompt, Handler}, State#state.prompts),
    {reply, ok, State#state{prompts = NewPrompts}};

handle_call({add_prompt_with_args, Name, Handler, Arguments}, _From, State) ->
    Prompt = #mcp_prompt{
        name = Name,
        arguments = Arguments
    },
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
    Notification = #mcp_progress_notification{
        progress_token = #mcp_progress_token{token = Token},
        progress = Progress,
        total = Total
    },
    send_progress_notification(State, Token, Progress, Total),
    NewTokens = maps:put(Token, Notification, State#state.progress_tokens),
    {noreply, State#state{progress_tokens = NewTokens}};

handle_cast({notify_resource_updated, Uri, Metadata}, State) ->
    notify_subscribers(Uri, Metadata, State),
    {noreply, State};

handle_cast(notify_resources_changed, State) ->
    send_notification(State, <<"resources/list_changed">>, #{}),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.

handle_info({transport_message, Data}, State) ->
    case erlmcp_json_rpc:decode_message(Data) of
        {ok, #json_rpc_request{id = Id, method = Method, params = Params}} ->
            handle_request(Id, Method, Params, State);
        {ok, #json_rpc_notification{method = Method, params = Params}} ->
            handle_notification(Method, Params, State);
        {error, Reason} ->
            logger:error("Failed to decode message: ~p", [Reason]),
            {noreply, State}
    end;

handle_info({'EXIT', Pid, Reason}, State) when Pid =:= State#state.transport_state ->
    logger:error("Transport process died: ~p", [Reason]),
    {stop, {transport_died, Reason}, State};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    close_transport(State),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions - Request Handling
%%====================================================================

-spec handle_request(json_rpc_id(), binary(), json_rpc_params(), state()) -> 
    {noreply, state()}.

handle_request(Id, <<"initialize">>, _Params, State) ->
    Response = build_initialize_response(State#state.capabilities),
    send_response(State, Id, Response),
    {noreply, State#state{initialized = true}};

handle_request(Id, <<"resources/list">>, _Params, State) ->
    Resources = list_all_resources(State),
    send_response(State, Id, #{<<"resources">> => Resources}),
    {noreply, State};

handle_request(Id, <<"resources/read">>, Params, State) ->
    case maps:get(<<"uri">>, Params, undefined) of
        undefined ->
            send_error(State, Id, -32602, <<"Missing uri parameter">>);
        Uri ->
            handle_read_resource(Id, Uri, State)
    end,
    {noreply, State};

handle_request(Id, <<"tools/list">>, _Params, State) ->
    Tools = list_all_tools(State),
    send_response(State, Id, #{<<"tools">> => Tools}),
    {noreply, State};

handle_request(Id, <<"tools/call">>, Params, State) ->
    Name = maps:get(<<"name">>, Params, undefined),
    Args = maps:get(<<"arguments">>, Params, #{}),
    case {Name, Args} of
        {undefined, _} ->
            send_error(State, Id, -32602, <<"Missing tool name">>);
        {ToolName, Arguments} ->
            handle_tool_call(Id, ToolName, Arguments, State)
    end,
    {noreply, State};

handle_request(Id, <<"resources/templates/list">>, _Params, State) ->
    Templates = list_all_templates(State),
    send_response(State, Id, #{<<"resourceTemplates">> => Templates}),
    {noreply, State};

handle_request(Id, <<"resources/subscribe">>, Params, State) ->
    case maps:get(<<"uri">>, Params, undefined) of
        undefined ->
            send_error(State, Id, -32602, <<"Missing uri parameter">>);
        Uri ->
            NewSubscriptions = add_subscription(Uri, self(), State#state.subscriptions),
            send_response(State, Id, #{}),
            {noreply, State#state{subscriptions = NewSubscriptions}}
    end;

handle_request(Id, <<"resources/unsubscribe">>, Params, State) ->
    case maps:get(<<"uri">>, Params, undefined) of
        undefined ->
            send_error(State, Id, -32602, <<"Missing uri parameter">>);
        Uri ->
            NewSubscriptions = remove_subscription(Uri, State#state.subscriptions),
            send_response(State, Id, #{}),
            {noreply, State#state{subscriptions = NewSubscriptions}}
    end;

handle_request(Id, <<"prompts/list">>, _Params, State) ->
    Prompts = list_all_prompts(State),
    send_response(State, Id, #{<<"prompts">> => Prompts}),
    {noreply, State};

handle_request(Id, <<"prompts/get">>, Params, State) ->
    case maps:get(<<"name">>, Params, undefined) of
        undefined ->
            send_error(State, Id, -32602, <<"Missing prompt name">>);
        Name ->
            Arguments = maps:get(<<"arguments">>, Params, #{}),
            handle_get_prompt(Id, Name, Arguments, State)
    end,
    {noreply, State};

handle_request(Id, _Method, _Params, State) ->
    send_error(State, Id, -32601, <<"Method not found">>),
    {noreply, State}.

-spec handle_notification(binary(), map(), state()) -> {noreply, state()}.
handle_notification(_Method, _Params, State) ->
    {noreply, State}.

%%====================================================================
%% Internal functions - Transport
%%====================================================================

-spec init_transport(transport_opts()) -> 
    {ok, module(), term()} | {error, term()}.
init_transport({stdio, _Opts}) ->
    {ok, erlmcp_transport_stdio, self()};
init_transport({tcp, Opts}) ->
    {ok, erlmcp_transport_tcp, Opts};
init_transport({http, Opts}) ->
    case erlmcp_transport_http:init(Opts) of
        {ok, State} -> {ok, erlmcp_transport_http, State};
        {error, _} = Error -> Error
    end.

-spec close_transport(state()) -> ok.
close_transport(#state{transport = Transport, transport_state = TransportState}) ->
    catch Transport:close(TransportState),
    ok.

-spec send_message(state(), binary()) -> ok | {error, term()}.
send_message(#state{transport = Transport, transport_state = TransportState}, Message) ->
    Transport:send(TransportState, Message).

-spec send_response(state(), json_rpc_id(), map()) -> ok | {error, term()}.
send_response(State, Id, Result) ->
    Json = erlmcp_json_rpc:encode_response(Id, Result),
    send_message(State, Json).

-spec send_error(state(), json_rpc_id(), integer(), binary()) -> ok | {error, term()}.
send_error(State, Id, Code, Message) ->
    Json = erlmcp_json_rpc:encode_error_response(Id, Code, Message),
    send_message(State, Json).

-spec send_notification(state(), binary(), map()) -> ok | {error, term()}.
send_notification(State, Method, Params) ->
    Json = erlmcp_json_rpc:encode_notification(Method, Params),
    send_message(State, Json).

-spec send_progress_notification(state(), binary() | integer(), float(), float()) -> 
    ok | {error, term()}.
send_progress_notification(State, Token, Progress, Total) ->
    Params = #{
        <<"progressToken">> => Token,
        <<"progress">> => Progress,
        <<"total">> => Total
    },
    send_notification(State, <<"notifications/progress">>, Params).

%%====================================================================
%% Internal functions - Response Building
%%====================================================================

-spec build_initialize_response(#mcp_server_capabilities{}) -> map().
build_initialize_response(Capabilities) ->
    #{
        <<"protocolVersion">> => ?MCP_VERSION,
        <<"capabilities">> => encode_server_capabilities(Capabilities),
        <<"serverInfo">> => #{
            <<"name">> => <<"erlmcp">>,
            <<"version">> => <<"0.1.0">>
        }
    }.

-spec encode_server_capabilities(#mcp_server_capabilities{}) -> map().
encode_server_capabilities(#mcp_server_capabilities{} = Caps) ->
    Base = #{},
    Base1 = maybe_add_server_capability(Base, <<"resources">>, 
                                        Caps#mcp_server_capabilities.resources,
                                        #{<<"subscribe">> => true, <<"listChanged">> => true}),
    Base2 = maybe_add_server_capability(Base1, <<"tools">>, 
                                        Caps#mcp_server_capabilities.tools, #{}),
    Base3 = maybe_add_server_capability(Base2, <<"prompts">>, 
                                        Caps#mcp_server_capabilities.prompts,
                                        #{<<"listChanged">> => true}),
    maybe_add_server_capability(Base3, <<"logging">>, 
                                Caps#mcp_server_capabilities.logging, #{}).

-spec maybe_add_server_capability(map(), binary(), #mcp_capability{} | undefined, map()) -> map().
maybe_add_server_capability(Map, _Key, undefined, _Value) ->
    Map;
maybe_add_server_capability(Map, Key, #mcp_capability{enabled = true}, Value) ->
    Map#{Key => Value};
maybe_add_server_capability(Map, _Key, _, _Value) ->
    Map.

%%====================================================================
%% Internal functions - Resource Handling
%%====================================================================

-spec list_all_resources(state()) -> [map()].
list_all_resources(State) ->
    maps:fold(fun(_Uri, {Resource, _Handler}, Acc) ->
        [encode_resource(Resource) | Acc]
    end, [], State#state.resources).

-spec list_all_templates(state()) -> [map()].
list_all_templates(State) ->
    maps:fold(fun(_UriTemplate, {Template, _Handler}, Acc) ->
        [encode_resource_template(Template) | Acc]
    end, [], State#state.resource_templates).

-spec encode_resource(#mcp_resource{}) -> map().
encode_resource(#mcp_resource{} = Resource) ->
    Base = #{
        <<"uri">> => Resource#mcp_resource.uri,
        <<"name">> => Resource#mcp_resource.name
    },
    Base1 = maybe_add_field(Base, <<"description">>, Resource#mcp_resource.description),
    Base2 = maybe_add_field(Base1, <<"mimeType">>, Resource#mcp_resource.mime_type),
    maybe_add_field(Base2, <<"metadata">>, Resource#mcp_resource.metadata).

-spec encode_resource_template(#mcp_resource_template{}) -> map().
encode_resource_template(#mcp_resource_template{} = Template) ->
    Base = #{
        <<"uriTemplate">> => Template#mcp_resource_template.uri_template,
        <<"name">> => Template#mcp_resource_template.name
    },
    Base1 = maybe_add_field(Base, <<"description">>, Template#mcp_resource_template.description),
    maybe_add_field(Base1, <<"mimeType">>, Template#mcp_resource_template.mime_type).

-spec maybe_add_field(map(), binary(), term()) -> map().
maybe_add_field(Map, _Key, undefined) ->
    Map;
maybe_add_field(Map, Key, Value) ->
    Map#{Key => Value}.

-spec handle_read_resource(json_rpc_id(), binary(), state()) -> ok.
handle_read_resource(Id, Uri, State) ->
    case find_resource(Uri, State) of
        {ok, {Resource, Handler}} ->
            try
                Content = Handler(Uri),
                ContentItem = encode_content_item(Content, Resource, Uri),
                send_response(State, Id, #{<<"contents">> => [ContentItem]})
            catch
                Class:Reason:Stack ->
                    logger:error("Resource handler crashed: ~p:~p~n~p", 
                                 [Class, Reason, Stack]),
                    send_error(State, Id, -32603, <<"Internal error">>)
            end;
        {error, not_found} ->
            send_error(State, Id, -32602, <<"Resource not found">>)
    end.

-spec find_resource(binary(), state()) -> 
    {ok, {#mcp_resource{} | #mcp_resource_template{}, resource_handler()}} | 
    {error, not_found}.
find_resource(Uri, State) ->
    case maps:get(Uri, State#state.resources, undefined) of
        undefined ->
            find_resource_by_template(Uri, State);
        Resource ->
            {ok, Resource}
    end.

-spec find_resource_by_template(binary(), state()) -> 
    {ok, {#mcp_resource_template{}, resource_handler()}} | 
    {error, not_found}.
find_resource_by_template(Uri, State) ->
    Templates = maps:to_list(State#state.resource_templates),
    find_matching_template(Uri, Templates).

-spec find_matching_template(binary(), [{binary(), {#mcp_resource_template{}, resource_handler()}}]) ->
    {ok, {#mcp_resource_template{}, resource_handler()}} | {error, not_found}.
find_matching_template(_Uri, []) ->
    {error, not_found};
find_matching_template(Uri, [{UriTemplate, TemplateData} | Rest]) ->
    case match_uri_template(Uri, UriTemplate) of
        {ok, _Params} ->
            {ok, TemplateData};
        nomatch ->
            find_matching_template(Uri, Rest)
    end.

-spec match_uri_template(binary(), binary()) -> {ok, map()} | nomatch.
match_uri_template(Uri, UriTemplate) ->
    Pattern = uri_template_to_regex(UriTemplate),
    case re:run(Uri, Pattern, [{capture, all, binary}]) of
        {match, _Captures} ->
            {ok, #{}};
        nomatch ->
            nomatch
    end.

-spec uri_template_to_regex(binary()) -> binary().
uri_template_to_regex(UriTemplate) ->
    Escaped = re:replace(UriTemplate, <<"\\{[^}]+\\}">>, <<"([^/]+)">>, 
                         [global, {return, binary}]),
    <<"^", Escaped/binary, "$">>.

-spec encode_content_item(binary() | #mcp_content{}, 
                          #mcp_resource{} | #mcp_resource_template{}, 
                          binary()) -> map().
encode_content_item(#mcp_content{} = Content, _Resource, _Uri) ->
    encode_content(Content);
encode_content_item(BinaryContent, Resource, Uri) when is_binary(BinaryContent) ->
    #{
        <<"uri">> => Uri,
        <<"mimeType">> => get_mime_type(Resource),
        <<"text">> => BinaryContent
    }.

-spec get_mime_type(#mcp_resource{} | #mcp_resource_template{}) -> binary().
get_mime_type(#mcp_resource{mime_type = MimeType}) ->
    MimeType;
get_mime_type(#mcp_resource_template{mime_type = MimeType}) ->
    MimeType.

-spec encode_content(#mcp_content{}) -> map().
encode_content(#mcp_content{} = Content) ->
    Base = #{<<"type">> => Content#mcp_content.type},
    Base1 = maybe_add_field(Base, <<"text">>, Content#mcp_content.text),
    Base2 = maybe_add_field(Base1, <<"data">>, Content#mcp_content.data),
    maybe_add_field(Base2, <<"mimeType">>, Content#mcp_content.mime_type).

%%====================================================================
%% Internal functions - Tool Handling
%%====================================================================

-spec list_all_tools(state()) -> [map()].
list_all_tools(State) ->
    maps:fold(fun(_Name, {Tool, _Handler, _Schema}, Acc) ->
        [encode_tool(Tool) | Acc]
    end, [], State#state.tools).

-spec encode_tool(#mcp_tool{}) -> map().
encode_tool(#mcp_tool{} = Tool) ->
    Base = #{
        <<"name">> => Tool#mcp_tool.name,
        <<"description">> => Tool#mcp_tool.description
    },
    maybe_add_field(Base, <<"inputSchema">>, Tool#mcp_tool.input_schema).

-spec handle_tool_call(json_rpc_id(), binary(), map(), state()) -> ok.
handle_tool_call(Id, Name, Arguments, State) ->
    case maps:get(Name, State#state.tools, undefined) of
        undefined ->
            send_error(State, Id, -32602, <<"Tool not found">>);
        {_Tool, Handler, Schema} ->
            case validate_tool_input(Arguments, Schema) of
                ok ->
                    execute_tool(Id, Handler, Arguments, State);
                {error, ValidationError} ->
                    send_error(State, Id, -32602, ValidationError)
            end
    end.

-spec validate_tool_input(map(), map() | undefined) -> ok | {error, binary()}.
validate_tool_input(_Args, undefined) ->
    ok;
validate_tool_input(Args, Schema) ->
    case jesse:validate(Schema, Args) of
        {ok, _} ->
            ok;
        {error, ValidationErrors} ->
            ErrorMsg = format_validation_errors(ValidationErrors),
            {error, ErrorMsg}
    end.

-spec format_validation_errors(list()) -> binary().
format_validation_errors(Errors) ->
    ErrorStrings = [format_single_error(Error) || Error <- Errors],
    iolist_to_binary(string:join(ErrorStrings, "; ")).

-spec format_single_error(term()) -> string().
format_single_error({data_invalid, Schema, Error, Data}) ->
    io_lib:format("Validation error: ~p for data ~p with schema ~p", 
                  [Error, Data, Schema]);
format_single_error(Error) ->
    io_lib:format("Validation error: ~p", [Error]).

-spec execute_tool(json_rpc_id(), tool_handler(), map(), state()) -> ok.
execute_tool(Id, Handler, Arguments, State) ->
    try
        Result = Handler(Arguments),
        ContentList = normalize_tool_result(Result),
        send_response(State, Id, #{<<"content">> => ContentList})
    catch
        Class:Reason:Stack ->
            logger:error("Tool handler crashed: ~p:~p~n~p", 
                         [Class, Reason, Stack]),
            send_error(State, Id, -32603, <<"Internal error">>)
    end.

-spec normalize_tool_result(term()) -> [map()].
normalize_tool_result(#mcp_content{} = Content) ->
    [encode_content(Content)];
normalize_tool_result(BinaryResult) when is_binary(BinaryResult) ->
    [#{<<"type">> => <<"text">>, <<"text">> => BinaryResult}];
normalize_tool_result(ResultList) when is_list(ResultList) ->
    [encode_content(C) || C <- ResultList].

%%====================================================================
%% Internal functions - Prompt Handling
%%====================================================================

-spec list_all_prompts(state()) -> [map()].
list_all_prompts(State) ->
    maps:fold(fun(_Name, {Prompt, _Handler}, Acc) ->
        [encode_prompt(Prompt) | Acc]
    end, [], State#state.prompts).

-spec encode_prompt(#mcp_prompt{}) -> map().
encode_prompt(#mcp_prompt{} = Prompt) ->
    Base = #{<<"name">> => Prompt#mcp_prompt.name},
    Base1 = maybe_add_field(Base, <<"description">>, Prompt#mcp_prompt.description),
    case Prompt#mcp_prompt.arguments of
        undefined ->
            Base1;
        Args ->
            Base1#{<<"arguments">> => [encode_prompt_argument(Arg) || Arg <- Args]}
    end.

-spec encode_prompt_argument(#mcp_prompt_argument{}) -> map().
encode_prompt_argument(#mcp_prompt_argument{} = Arg) ->
    Base = #{
        <<"name">> => Arg#mcp_prompt_argument.name,
        <<"required">> => Arg#mcp_prompt_argument.required
    },
    maybe_add_field(Base, <<"description">>, Arg#mcp_prompt_argument.description).

-spec handle_get_prompt(json_rpc_id(), binary(), map(), state()) -> ok.
handle_get_prompt(Id, Name, Arguments, State) ->
    case maps:get(Name, State#state.prompts, undefined) of
        undefined ->
            send_error(State, Id, -32602, <<"Prompt not found">>);
        {Prompt, Handler} ->
            execute_prompt(Id, Prompt, Handler, Arguments, State)
    end.

-spec execute_prompt(json_rpc_id(), #mcp_prompt{}, prompt_handler(), map(), state()) -> ok.
execute_prompt(Id, Prompt, Handler, Arguments, State) ->
    try
        Result = Handler(Arguments),
        Messages = normalize_prompt_result(Result),
        Response = #{
            <<"messages">> => Messages
        },
        Response1 = maybe_add_field(Response, <<"description">>, 
                                    Prompt#mcp_prompt.description),
        send_response(State, Id, Response1)
    catch
        Class:Reason:Stack ->
            logger:error("Prompt handler crashed: ~p:~p~n~p", 
                         [Class, Reason, Stack]),
            send_error(State, Id, -32603, <<"Internal error">>)
    end.

-spec normalize_prompt_result(term()) -> [map()].
normalize_prompt_result(BinaryResult) when is_binary(BinaryResult) ->
    [#{
        <<"role">> => <<"user">>,
        <<"content">> => #{
            <<"type">> => <<"text">>,
            <<"text">> => BinaryResult
        }
    }];
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
            Params = #{
                <<"uri">> => Uri,
                <<"metadata">> => Metadata
            },
            sets:fold(fun(Subscriber, _) ->
                Subscriber ! {resource_updated, Uri, Metadata},
                ok
            end, ok, Subscribers),
            send_notification(State, <<"resources/updated">>, Params)
    end.