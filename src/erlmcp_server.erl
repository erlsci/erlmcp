-module(erlmcp_server).

-behaviour(gen_server).

-include_lib("kernel/include/logger.hrl").

%% API
-export([start_link/1,
         catalog_table/1,
         register_session/2, unregister_session/2,
         register_tool/2, unregister_tool/2,
         register_resource/2, unregister_resource/2,
         register_resource_template/2, unregister_resource_template/2,
         register_prompt/2, unregister_prompt/2,
         register_handler/2]).

%% ETS read helpers (hot path — no message passing)
-export([get_tools/1, get_tool/2,
         get_resources/1, get_resource/2,
         get_resource_templates/1,
         get_prompts/1, get_prompt/2,
         get_handlers/1,
         get_server_info/1, get_capabilities/1]).

%% Server identity (gen_server call — not hot path)
-export([get_identity/1, get_custom_instructions/1]).

%% gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-opaque server() :: pid().
-export_type([server/0]).

-record(state, {
    tab :: ets:tid(),
    sessions = [] :: [pid()],
    identity = #{} :: map()
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link(map()) -> {ok, server()} | {error, term()} | ignore.
start_link(Config) when is_map(Config) ->
    gen_server:start_link(?MODULE, Config, []).

-spec catalog_table(server()) -> ets:tid().
catalog_table(Server) ->
    gen_server:call(Server, catalog_table).

-spec register_session(server(), pid()) -> ok.
register_session(Server, Session) when is_pid(Session) ->
    gen_server:call(Server, {register_session, Session}).

-spec unregister_session(server(), pid()) -> ok.
unregister_session(Server, Session) when is_pid(Session) ->
    gen_server:call(Server, {unregister_session, Session}).

-spec register_tool(server(), map()) -> ok | {error, {invalid_tool_spec, term()}}.
register_tool(Server, ToolSpec) when is_map(ToolSpec) ->
    case validate_tool_spec(ToolSpec) of
        ok -> gen_server:call(Server, {register_tool, ToolSpec});
        {error, _} = Err -> Err
    end.

-spec unregister_tool(server(), binary()) -> ok.
unregister_tool(Server, ToolName) when is_binary(ToolName) ->
    gen_server:call(Server, {unregister_tool, ToolName}).

-spec register_resource(server(), map()) -> ok | {error, {invalid_resource_spec, term()}}.
register_resource(Server, Spec) when is_map(Spec) ->
    case validate_resource_spec(Spec) of
        ok -> gen_server:call(Server, {register_resource, Spec});
        {error, _} = Err -> Err
    end.

-spec unregister_resource(server(), binary()) -> ok.
unregister_resource(Server, Uri) when is_binary(Uri) ->
    gen_server:call(Server, {unregister_resource, Uri}).

-spec register_resource_template(server(), map()) -> ok | {error, {invalid_resource_template_spec, term()}}.
register_resource_template(Server, Spec) when is_map(Spec) ->
    case validate_resource_template_spec(Spec) of
        ok -> gen_server:call(Server, {register_resource_template, Spec});
        {error, _} = Err -> Err
    end.

-spec unregister_resource_template(server(), binary()) -> ok.
unregister_resource_template(Server, UriTemplate) when is_binary(UriTemplate) ->
    gen_server:call(Server, {unregister_resource_template, UriTemplate}).

-spec register_prompt(server(), map()) -> ok | {error, {invalid_prompt_spec, term()}}.
register_prompt(Server, Spec) when is_map(Spec) ->
    case validate_prompt_spec(Spec) of
        ok -> gen_server:call(Server, {register_prompt, Spec});
        {error, _} = Err -> Err
    end.

-spec unregister_prompt(server(), binary()) -> ok.
unregister_prompt(Server, Name) when is_binary(Name) ->
    gen_server:call(Server, {unregister_prompt, Name}).

-spec register_handler(server(), module()) -> ok.
register_handler(Server, Module) when is_atom(Module) ->
    gen_server:call(Server, {register_handler, Module}).

-spec get_identity(server()) -> map().
get_identity(Server) ->
    gen_server:call(Server, get_identity).

-spec get_custom_instructions(server()) -> binary() | undefined.
get_custom_instructions(Server) ->
    gen_server:call(Server, get_custom_instructions).

%%====================================================================
%% ETS read helpers — called by sessions on the hot path
%%====================================================================

-spec get_tools(ets:tid() | undefined) -> #{binary() => map()}.
get_tools(undefined) -> #{};
get_tools(Tab) ->
    ets_get_map(Tab, tools).

-spec get_tool(ets:tid() | undefined, binary()) -> {ok, map()} | error.
get_tool(undefined, _Name) -> error;
get_tool(Tab, Name) ->
    case maps:find(Name, ets_get_map(Tab, tools)) of
        {ok, _} = Ok -> Ok;
        error -> error
    end.

-spec get_resources(ets:tid() | undefined) -> #{binary() => map()}.
get_resources(undefined) -> #{};
get_resources(Tab) ->
    ets_get_map(Tab, resources).

-spec get_resource(ets:tid() | undefined, binary()) -> {ok, map()} | error.
get_resource(undefined, _Uri) -> error;
get_resource(Tab, Uri) ->
    case maps:find(Uri, ets_get_map(Tab, resources)) of
        {ok, _} = Ok -> Ok;
        error -> error
    end.

-spec get_resource_templates(ets:tid() | undefined) -> #{binary() => map()}.
get_resource_templates(undefined) -> #{};
get_resource_templates(Tab) ->
    ets_get_map(Tab, resource_templates).

-spec get_prompts(ets:tid() | undefined) -> #{binary() => map()}.
get_prompts(undefined) -> #{};
get_prompts(Tab) ->
    ets_get_map(Tab, prompts).

-spec get_prompt(ets:tid() | undefined, binary()) -> {ok, map()} | error.
get_prompt(undefined, _Name) -> error;
get_prompt(Tab, Name) ->
    case maps:find(Name, ets_get_map(Tab, prompts)) of
        {ok, _} = Ok -> Ok;
        error -> error
    end.

-spec get_handlers(ets:tid() | undefined) -> map().
get_handlers(undefined) -> #{};
get_handlers(Tab) ->
    ets_get_map(Tab, handlers).

-spec get_server_info(ets:tid() | undefined) -> erlmcp_model:peer_info().
get_server_info(undefined) ->
    erlmcp_model:make_server_info(<<"erlmcp">>, <<"0.6.0">>);
get_server_info(Tab) ->
    case ets:lookup(Tab, server_info) of
        [{server_info, Info}] -> Info;
        [] -> erlmcp_model:make_server_info(<<"erlmcp">>, <<"0.6.0">>)
    end.

-spec get_capabilities(ets:tid() | undefined) -> map().
get_capabilities(undefined) -> #{};
get_capabilities(Tab) ->
    ets_get_map(Tab, capabilities).

%%====================================================================
%% gen_server callbacks
%%====================================================================

-spec init(map()) -> {ok, #state{}}.
init(Config) ->
    Tab = ets:new(erlmcp_catalog, [set, protected]),
    ets:insert(Tab, {tools, #{}}),
    ets:insert(Tab, {resources, #{}}),
    ets:insert(Tab, {resource_templates, #{}}),
    ets:insert(Tab, {prompts, #{}}),
    ets:insert(Tab, {handlers, #{}}),
    Name = maps:get(name, Config, <<"erlmcp">>),
    Version = maps:get(version, Config, <<"0.6.0">>),
    ets:insert(Tab, {server_info, erlmcp_model:make_server_info(Name, Version)}),
    Caps = maps:get(capabilities, Config, #{}),
    ets:insert(Tab, {capabilities, Caps}),
    Identity = maps:with([name, version, purpose, source, docs], Config),
    CustomInstr = maps:get(instructions, Config, undefined),
    ets:insert(Tab, {custom_instructions, CustomInstr}),
    State = #state{tab = Tab, identity = Identity},
    State1 = init_tools(Config, State),
    State2 = init_resources(Config, State1),
    State3 = init_prompts(Config, State2),
    State4 = init_handler(Config, State3),
    State5 = init_handlers(Config, State4),
    {ok, State5}.

handle_call(catalog_table, _From, #state{tab = Tab} = State) ->
    {reply, Tab, State};
handle_call({register_session, Session}, _From, #state{sessions = S} = State) ->
    monitor(process, Session),
    {reply, ok, State#state{sessions = [Session | S]}};
handle_call({unregister_session, Session}, _From, #state{sessions = S} = State) ->
    {reply, ok, State#state{sessions = lists:delete(Session, S)}};
handle_call({register_tool, ToolSpec}, _From, State) ->
    Name = maps:get(name, ToolSpec),
    update_map(State#state.tab, tools, Name, ToolSpec),
    notify_sessions(State, <<"notifications/tools/list_changed">>),
    {reply, ok, State};
handle_call({unregister_tool, ToolName}, _From, State) ->
    remove_from_map(State#state.tab, tools, ToolName),
    notify_sessions(State, <<"notifications/tools/list_changed">>),
    {reply, ok, State};
handle_call({register_resource, Spec}, _From, State) ->
    Uri = maps:get(uri, Spec),
    update_map(State#state.tab, resources, Uri, Spec),
    notify_sessions(State, <<"notifications/resources/list_changed">>),
    {reply, ok, State};
handle_call({unregister_resource, Uri}, _From, State) ->
    remove_from_map(State#state.tab, resources, Uri),
    notify_sessions(State, <<"notifications/resources/list_changed">>),
    {reply, ok, State};
handle_call({register_resource_template, Spec}, _From, State) ->
    UriT = maps:get(uri_template, Spec),
    update_map(State#state.tab, resource_templates, UriT, Spec),
    notify_sessions(State, <<"notifications/resources/list_changed">>),
    {reply, ok, State};
handle_call({unregister_resource_template, UriTemplate}, _From, State) ->
    remove_from_map(State#state.tab, resource_templates, UriTemplate),
    notify_sessions(State, <<"notifications/resources/list_changed">>),
    {reply, ok, State};
handle_call({register_prompt, Spec}, _From, State) ->
    Name = maps:get(name, Spec),
    update_map(State#state.tab, prompts, Name, Spec),
    notify_sessions(State, <<"notifications/prompts/list_changed">>),
    {reply, ok, State};
handle_call({unregister_prompt, Name}, _From, State) ->
    remove_from_map(State#state.tab, prompts, Name),
    notify_sessions(State, <<"notifications/prompts/list_changed">>),
    {reply, ok, State};
handle_call({register_handler, Module}, _From, State) ->
    ToolSpecs = Module:tools(),
    Tab = State#state.tab,
    lists:foreach(fun(Spec) ->
        ToolName = maps:get(name, Spec),
        update_map(Tab, tools, ToolName, Spec#{handler_module => Module})
    end, ToolSpecs),
    notify_sessions(State, <<"notifications/tools/list_changed">>),
    {reply, ok, State};
handle_call(get_identity, _From, State) ->
    {reply, State#state.identity, State};
handle_call(get_custom_instructions, _From, #state{tab = Tab} = State) ->
    [{custom_instructions, V}] = ets:lookup(Tab, custom_instructions),
    {reply, V, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #state{sessions = S} = State) ->
    {noreply, State#state{sessions = lists:delete(Pid, S)}};
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal — registration validation
%%====================================================================

-spec validate_tool_spec(map()) -> ok | {error, {invalid_tool_spec, term()}}.
validate_tool_spec(Spec) ->
    case check_required_keys(Spec, [{name, binary}, {description, binary}]) of
        ok -> validate_tool_handler(Spec);
        {error, Reason} -> {error, {invalid_tool_spec, Reason}}
    end.

validate_tool_handler(Spec) ->
    Handler = maps:get(handler, Spec, undefined),
    HandlerMod = maps:get(handler_module, Spec, undefined),
    case {Handler, HandlerMod} of
        {undefined, undefined} ->
            {error, {invalid_tool_spec, missing_handler}};
        {F, _} when is_function(F, 2) ->
            validate_protocol_features(Spec, invalid_tool_spec);
        {{M, F}, _} when is_atom(M), is_atom(F) ->
            validate_protocol_features(Spec, invalid_tool_spec);
        {undefined, M} when is_atom(M) ->
            validate_protocol_features(Spec, invalid_tool_spec);
        _ ->
            {error, {invalid_tool_spec, invalid_handler}}
    end.

-spec validate_resource_spec(map()) -> ok | {error, {invalid_resource_spec, term()}}.
validate_resource_spec(Spec) ->
    case check_required_keys(Spec, [{uri, binary}, {name, binary}]) of
        ok -> check_has_handler(Spec, invalid_resource_spec);
        {error, Reason} -> {error, {invalid_resource_spec, Reason}}
    end.

-spec validate_resource_template_spec(map()) -> ok | {error, {invalid_resource_template_spec, term()}}.
validate_resource_template_spec(Spec) ->
    case check_required_keys(Spec, [{uri_template, binary}, {name, binary}]) of
        ok -> check_has_handler(Spec, invalid_resource_template_spec);
        {error, Reason} -> {error, {invalid_resource_template_spec, Reason}}
    end.

-spec validate_prompt_spec(map()) -> ok | {error, {invalid_prompt_spec, term()}}.
validate_prompt_spec(Spec) ->
    case check_required_keys(Spec, [{name, binary}]) of
        ok -> check_has_handler(Spec, invalid_prompt_spec);
        {error, Reason} -> {error, {invalid_prompt_spec, Reason}}
    end.

check_required_keys(_Spec, []) ->
    ok;
check_required_keys(Spec, [{Key, binary} | Rest]) ->
    case maps:get(Key, Spec, undefined) of
        V when is_binary(V), byte_size(V) > 0 ->
            check_required_keys(Spec, Rest);
        undefined ->
            {error, {missing, Key}};
        <<>> ->
            {error, {empty, Key}};
        _ ->
            {error, {bad_type, Key, binary}}
    end.

check_has_handler(Spec, ErrorTag) ->
    case maps:get(handler, Spec, undefined) of
        F when is_function(F) -> validate_protocol_features(Spec, ErrorTag);
        {M, F} when is_atom(M), is_atom(F) -> validate_protocol_features(Spec, ErrorTag);
        undefined -> {error, {ErrorTag, missing_handler}};
        _ -> {error, {ErrorTag, invalid_handler}}
    end.

validate_protocol_features(Spec, ErrorTag) ->
    case maps:get(protocol_features, Spec, undefined) of
        undefined -> ok;
        PF when is_list(PF) ->
            case lists:all(fun is_atom/1, PF) of
                true -> ok;
                false -> {error, {ErrorTag, {invalid_protocol_features, PF}}}
            end;
        Other ->
            {error, {ErrorTag, {invalid_protocol_features, Other}}}
    end.

%%====================================================================
%% Internal — ETS helpers
%%====================================================================

ets_get_map(Tab, Key) ->
    case ets:lookup(Tab, Key) of
        [{Key, Map}] -> Map;
        [] -> #{}
    end.

update_map(Tab, Category, Key, Value) ->
    Map = ets_get_map(Tab, Category),
    ets:insert(Tab, {Category, maps:put(Key, Value, Map)}).

remove_from_map(Tab, Category, Key) ->
    Map = ets_get_map(Tab, Category),
    ets:insert(Tab, {Category, maps:remove(Key, Map)}).

notify_sessions(#state{sessions = Sessions}, Method) ->
    lists:foreach(fun(Session) ->
        Session ! {catalog_changed, Method}
    end, Sessions).

init_tools(Config, State) ->
    case maps:get(tools, Config, []) of
        Tools when is_list(Tools) ->
            Tab = State#state.tab,
            lists:foreach(fun(ToolSpec) ->
                Name = maps:get(name, ToolSpec),
                update_map(Tab, tools, Name, ToolSpec)
            end, Tools),
            State;
        _ ->
            State
    end.

init_resources(Config, State) ->
    case maps:get(resources, Config, []) of
        Resources when is_list(Resources) ->
            Tab = State#state.tab,
            lists:foreach(fun(Spec) ->
                Uri = maps:get(uri, Spec),
                update_map(Tab, resources, Uri, Spec)
            end, Resources),
            State;
        _ ->
            State
    end.

init_prompts(Config, State) ->
    case maps:get(prompts, Config, []) of
        Prompts when is_list(Prompts) ->
            Tab = State#state.tab,
            lists:foreach(fun(Spec) ->
                Name = maps:get(name, Spec),
                update_map(Tab, prompts, Name, Spec)
            end, Prompts),
            State;
        _ ->
            State
    end.

init_handler(Config, State) ->
    case maps:get(handler, Config, undefined) of
        undefined ->
            State;
        Module when is_atom(Module) ->
            ToolSpecs = Module:tools(),
            Tab = State#state.tab,
            lists:foreach(fun(Spec) ->
                ToolName = maps:get(name, Spec),
                update_map(Tab, tools, ToolName, Spec#{handler_module => Module})
            end, ToolSpecs),
            State
    end.

init_handlers(Config, State) ->
    case maps:get(handlers, Config, undefined) of
        undefined ->
            State;
        Handlers when is_map(Handlers) ->
            Tab = State#state.tab,
            ets:insert(Tab, {handlers, Handlers}),
            State
    end.
