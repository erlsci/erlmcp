%% -*- coding: utf-8 -*-
-module(calculator_server).

%% A runnable calculator MCP server demonstrating:
%%   - Tool registration via the erlmcp_server_handler behaviour
%%   - Discoverability (instructions + the directory tool)
%%   - Task support (long-running tool with progress + cancel)
%%   - Icons on tools
%%   - _meta passthrough
%%   - Structured output (outputSchema)

-behaviour(erlmcp_server_handler).

-export([start/0, start/1, slow_tool_spec/0, explain_tool_spec/0]).
-export([tools/0, handle_tool/3]).

-spec start() -> {ok, pid()} | {error, term()} | ignore.
start() ->
    start(#{}).

-spec start(map()) -> {ok, pid()} | {error, term()} | ignore.
start(Config) ->
    erlmcp:start_stdio_setup(calculator, Config#{
        name => <<"calculator">>,
        version => <<"0.6.0">>,
        purpose => <<"An arithmetic MCP server demonstrating handler behaviours, structured output, task support with progress/cancel, and server-initiated sampling.">>,
        source => <<"https://github.com/erlsci/erlmcp/tree/main/examples/calculator">>,
        handler => ?MODULE,
        tools => [erlmcp:make_directory_tool(), slow_tool_spec(), explain_tool_spec()]
    }).

%%====================================================================
%% erlmcp_server_handler callbacks
%%====================================================================

tools() ->
    OutSchema = erlmcp_schema:object([
        erlmcp_schema:field(<<"result">>, erlmcp_schema:number(), [required])
    ]),
    [
        #{name => <<"add">>,
          description => <<"Add two numbers">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to add two numbers">>,
          returns => <<"The sum of a and b">>,
          next => [<<"subtract">>, <<"multiply">>, <<"slow_compute">>, <<"explain">>],
          entry_point => true,
          icons => emoji_icon(<<"➕"/utf8>>),
          annotations => #{readOnlyHint => true}},
        #{name => <<"subtract">>,
          description => <<"Subtract b from a">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to subtract">>,
          returns => <<"The difference a - b">>,
          next => [<<"add">>],
          annotations => #{readOnlyHint => true}},
        #{name => <<"multiply">>,
          description => <<"Multiply two numbers">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to multiply">>,
          returns => <<"The product of a and b">>,
          next => [<<"divide">>],
          annotations => #{readOnlyHint => true}},
        #{name => <<"divide">>,
          description => <<"Divide a by b">>,
          input_schema => two_number_schema(),
          output_schema => OutSchema,
          category => <<"arithmetic">>,
          when_to_use => <<"When you need to divide">>,
          returns => <<"The quotient a / b">>,
          next => [<<"multiply">>],
          annotations => #{readOnlyHint => true}}
    ].

handle_tool(<<"add">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    R = A + B,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"subtract">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    R = A - B,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"multiply">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    R = A * B,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}};
handle_tool(<<"divide">>, #{<<"a">> := _A, <<"b">> := B}, _Ctx) when B == 0 ->
    {error, -32602, <<"Division by zero">>};
handle_tool(<<"divide">>, #{<<"a">> := A, <<"b">> := B}, _Ctx) ->
    R = A / B,
    {ok, erlmcp:text(format_num(R)), #{<<"result">> => R}}.

%%====================================================================
%% Task-enabled slow tool (demonstrates task + progress + cancel)
%%====================================================================

slow_tool_spec() ->
    #{name => <<"slow_compute">>,
      description => <<"A long-running computation (demonstrates tasks)">>,
      input_schema => erlmcp_schema:object([
          erlmcp_schema:field(<<"steps">>, erlmcp_schema:integer([{min, 1}, {max, 100}]),
              [required])
      ]),
      category => <<"demo">>,
      when_to_use => <<"When you want to demonstrate task support with progress">>,
      returns => <<"A completion message after all steps finish">>,
      summary => <<"Simulates a long-running job with progress notifications">>,
      next => [<<"add">>],
      icons => emoji_icon(<<"⏳"/utf8>>),
      task_support => optional,
      protocol_features => [tasks, progress],
      handler => fun slow_compute/2}.

explain_tool_spec() ->
    #{name => <<"explain">>,
      description => <<"Ask the connected client (Claude) to explain a calculation">>,
      input_schema => erlmcp_schema:object([
          erlmcp_schema:field(<<"expression">>, erlmcp_schema:string(),
              [required, {doc, <<"The math expression to explain (e.g. '2+3')">>}])
      ]),
      category => <<"demo">>,
      when_to_use => <<"When you want the client to generate an explanation (exercises server-to-client sampling)">>,
      returns => <<"The client's explanation of the expression">>,
      summary => <<"Demonstrates server-initiated sampling via request_peer">>,
      next => [<<"add">>],
      icons => emoji_icon(<<"💡"/utf8>>),
      protocol_features => [sampling],
      handler => fun explain_via_sampling/2}.

slow_compute(#{<<"steps">> := Steps}, Ctx) ->
    lists:foreach(fun(I) ->
        timer:sleep(50),
        erlmcp_ctx:report_progress(Ctx, I / Steps,
            <<"Step ", (integer_to_binary(I))/binary, "/",
              (integer_to_binary(Steps))/binary>>)
    end, lists:seq(1, Steps)),
    {ok, erlmcp:text(<<"Completed ", (integer_to_binary(Steps))/binary, " steps">>)}.

%%====================================================================
%% Server-initiated sampling (ENH-7: exercises server→client request_peer)
%%====================================================================

explain_via_sampling(#{<<"expression">> := Expr}, Ctx) ->
    Params = #{
        <<"messages">> => [
            #{<<"role">> => <<"user">>,
              <<"content">> => #{
                  <<"type">> => <<"text">>,
                  <<"text">> => <<"Explain this calculation step by step: ", Expr/binary>>
              }}
        ],
        <<"maxTokens">> => 200
    },
    case erlmcp_ctx:request_peer(Ctx, <<"sampling/createMessage">>, Params) of
        {ok, Result} ->
            Content = maps:get(<<"content">>, Result, #{}),
            Text = maps:get(<<"text">>, Content, <<"(no explanation)">>),
            {ok, erlmcp:text(Text)};
        {error, Reason} ->
            Msg = iolist_to_binary(io_lib:format("~p", [Reason])),
            {error, -32603, <<"Sampling failed: ", Msg/binary>>}
    end.

%%====================================================================
%% Internal
%%====================================================================

two_number_schema() ->
    erlmcp_schema:object([
        erlmcp_schema:field(<<"a">>, erlmcp_schema:number(), [required]),
        erlmcp_schema:field(<<"b">>, erlmcp_schema:number(), [required])
    ]).

%% Build a spec-conformant MCP `Icon` from an emoji glyph.
%%
%% The MCP schema's `Icon` requires a `src` URI (an HTTP/HTTPS URL or a
%% `data:` URI) and permits only `mimeType`, `sizes`, and `theme`. There is
%% no emoji icon variant. To keep the emoji flavour while emitting a real,
%% renderable icon, we wrap the glyph in a tiny inline SVG and embed it as a
%% base64-encoded `data:` URI. This demonstrates the genuine icon mechanism a
%% client can actually display. `Emoji` must be a valid UTF-8 binary (use the
%% `/utf8` literal modifier — without it the codepoint is truncated to a
%% single byte and the payload ships malformed UTF-8).
-spec emoji_icon(binary()) -> [map()].
emoji_icon(Emoji) when is_binary(Emoji) ->
    Svg = <<"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" "
            "viewBox=\"0 0 48 48\"><text x=\"24\" y=\"36\" font-size=\"34\" "
            "text-anchor=\"middle\">", Emoji/binary, "</text></svg>">>,
    Src = <<"data:image/svg+xml;base64,", (base64:encode(Svg))/binary>>,
    [#{<<"src">> => Src,
       <<"mimeType">> => <<"image/svg+xml">>,
       <<"sizes">> => [<<"any">>]}].

format_num(N) when is_integer(N) -> integer_to_binary(N);
format_num(N) when is_float(N) -> float_to_binary(N, [{decimals, 10}, compact]).
