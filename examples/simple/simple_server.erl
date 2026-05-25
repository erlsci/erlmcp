-module(simple_server).

%% A minimal MCP server demonstrating:
%%   - Inline tool registration (fun-based, no handler module)
%%   - A single resource + prompt
%%   - Full discoverability (wayfinding, directory tool)

-export([start/0, start/1, stop/1, register_all/1]).

-spec start() -> {ok, #{server := pid(), transport := pid()}}.
start() ->
    start(#{}).

-spec start(map()) -> {ok, #{server := pid(), transport := pid()}}.
start(Config) ->
    {ok, #{server := Server} = Result} =
        erlmcp:start_stdio_setup(simple, Config),
    register_all(Server),
    {ok, Result}.

-spec stop(pid()) -> ok.
stop(Server) ->
    gen_statem:stop(Server).

%%====================================================================
%% Registration — full discoverability wayfinding on every tool
%%====================================================================

register_all(Server) ->
    ok = erlmcp:add_tool(Server, erlmcp:make_directory_tool()),
    ok = erlmcp:add_tool(Server, #{
        name => <<"echo">>,
        description => <<"Echo the input back">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"text">>, erlmcp_schema:string(), [required])
        ]),
        category => <<"utility">>,
        when_to_use => <<"When you want to test connectivity or echo text">>,
        returns => <<"The input text, unchanged">>,
        summary => <<"Simple echo — returns its input">>,
        next => [<<"add">>],
        entry_point => true,
        annotations => #{readOnlyHint => true},
        handler => fun(#{<<"text">> := Text}, _Ctx) ->
            {ok, erlmcp:text(Text)}
        end
    }),
    ok = erlmcp:add_tool(Server, #{
        name => <<"add">>,
        description => <<"Add two numbers">>,
        input_schema => erlmcp_schema:object([
            erlmcp_schema:field(<<"a">>, erlmcp_schema:number(), [required]),
            erlmcp_schema:field(<<"b">>, erlmcp_schema:number(), [required])
        ]),
        category => <<"utility">>,
        when_to_use => <<"When you need to add two numbers">>,
        returns => <<"The sum of a and b">>,
        summary => <<"Basic addition">>,
        next => [<<"echo">>],
        annotations => #{readOnlyHint => true},
        handler => fun(#{<<"a">> := A, <<"b">> := B}, _Ctx) ->
            {ok, erlmcp:text(iolist_to_binary(io_lib:format("~p", [A + B])))}
        end
    }),
    ok = erlmcp:add_resource(Server, #{
        uri => <<"file://example.txt">>,
        name => <<"Example File">>,
        handler => fun(_Ctx) ->
            {ok, #{<<"uri">> => <<"file://example.txt">>,
                   <<"mimeType">> => <<"text/plain">>,
                   <<"text">> => <<"Hello from erlmcp!">>}}
        end
    }),
    ok = erlmcp:add_prompt(Server, #{
        name => <<"greet">>,
        description => <<"Generate a greeting">>,
        arguments => [
            #{name => <<"name">>, description => <<"Person to greet">>, required => true}
        ],
        handler => fun(#{<<"name">> := Name}, _Ctx) ->
            {ok, [
                #{<<"role">> => <<"user">>,
                  <<"content">> => #{<<"type">> => <<"text">>,
                                     <<"text">> => <<"Say hello to ", Name/binary>>}}
            ]}
        end
    }).
