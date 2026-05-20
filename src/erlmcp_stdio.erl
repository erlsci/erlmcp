% Fixed erlmcp_stdio.erl module
-module(erlmcp_stdio).

%% API exports
-export([start/0, start/1, stop/0, add_tool/3, add_tool/4, add_resource/3, add_resource/4,
         add_prompt/3, add_prompt/4, is_running/0]).

%%====================================================================
%% API Functions
%%====================================================================

-spec start() -> ok | {error, term()}.
start() ->
    start(#{}).

-spec start(map()) -> ok | {error, term()}.
start(Options) ->
    case erlmcp_sup:start_stdio_server(Options) of
        {ok, _Pid} ->
            ok;
        {error, {already_started, _Pid}} ->
            ok;
        Error ->
            Error
    end.

-spec stop() -> ok.
stop() ->
    erlmcp_sup:stop_stdio_server().

-spec add_tool(binary(), binary(), fun()) -> ok | {error, term()}.
add_tool(Name, Description, Handler) ->
    add_tool(Name, Description, Handler, undefined).

-spec add_tool(binary(), binary(), fun(), map() | undefined) -> ok | {error, term()}.
add_tool(Name, Description, Handler, Schema) ->
    case is_running() of
        true ->
            try
                gen_server:call(erlmcp_stdio_server, {add_tool, Name, Description, Handler, Schema})
            catch
                exit:{noproc, _} ->
                    {error, stdio_server_not_running};
                exit:{timeout, _} ->
                    {error, timeout}
            end;
        false ->
            {error, stdio_server_not_running}
    end.

-spec add_resource(binary(), binary(), fun()) -> ok | {error, term()}.
add_resource(Uri, Description, Handler) ->
    add_resource(Uri, Description, Handler, <<"text/plain">>).

-spec add_resource(binary(), binary(), fun(), binary()) -> ok | {error, term()}.
add_resource(Uri, Description, Handler, MimeType) ->
    case is_running() of
        true ->
            try
                gen_server:call(erlmcp_stdio_server,
                                {add_resource, Uri, Description, Handler, MimeType})
            catch
                exit:{noproc, _} ->
                    {error, stdio_server_not_running};
                exit:{timeout, _} ->
                    {error, timeout}
            end;
        false ->
            {error, stdio_server_not_running}
    end.

-spec add_prompt(binary(), binary(), fun()) -> ok | {error, term()}.
add_prompt(Name, Description, Handler) ->
    add_prompt(Name, Description, Handler, undefined).

-spec add_prompt(binary(), binary(), fun(), [map()] | undefined) -> ok | {error, term()}.
add_prompt(Name, Description, Handler, Arguments) ->
    case is_running() of
        true ->
            try
                gen_server:call(erlmcp_stdio_server,
                                {add_prompt, Name, Description, Handler, Arguments})
            catch
                exit:{noproc, _} ->
                    {error, stdio_server_not_running};
                exit:{timeout, _} ->
                    {error, timeout}
            end;
        false ->
            {error, stdio_server_not_running}
    end.

-spec is_running() -> boolean().
is_running() ->
    case whereis(erlmcp_stdio_server) of
        undefined ->
            false;
        Pid when is_pid(Pid) ->
            is_process_alive(Pid)
    end.
