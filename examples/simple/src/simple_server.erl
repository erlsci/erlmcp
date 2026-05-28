-module(simple_server).

%% A minimal MCP server demonstrating:
%%   - Config-driven tool/resource/prompt registration
%%   - Inline handlers (fun-based, no handler module)
%%   - Full discoverability (wayfinding, directory tool)

-export([start/0, start/1, register_all/1]).
-export([tools/0, resources/0, prompts/0]).

-spec start() -> {ok, pid()} | {error, term()}.
start() ->
    start(#{}).

-spec start(map()) -> {ok, pid()} | {error, term()}.
start(Config) ->
    erlmcp:start_stdio_setup(simple, Config#{
        tools => tools(),
        resources => resources(),
        prompts => prompts()
    }).

%% For test use — registers on an existing server
register_all(Server) ->
    lists:foreach(fun(T) -> ok = erlmcp:add_tool(Server, T) end, tools()),
    lists:foreach(fun(R) -> ok = erlmcp:add_resource(Server, R) end, resources()),
    lists:foreach(fun(P) -> ok = erlmcp:add_prompt(Server, P) end, prompts()).

%%====================================================================
%% Tool/resource/prompt definitions
%%====================================================================

tools() ->
    [erlmcp:make_directory_tool(),
     #{name => <<"echo">>,
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
       end},
     #{name => <<"add">>,
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
       end}].

resources() ->
    [#{uri => <<"file://example.txt">>,
       name => <<"Example File">>,
       handler => fun(_Ctx) ->
           {ok, #{<<"uri">> => <<"file://example.txt">>,
                  <<"mimeType">> => <<"text/plain">>,
                  <<"text">> => <<"Hello from erlmcp!">>}}
       end}].

prompts() ->
    [#{name => <<"greet">>,
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
       end}].
