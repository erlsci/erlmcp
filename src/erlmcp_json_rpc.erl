-module(erlmcp_json_rpc).

-include("erlmcp.hrl").

%% API exports
-export([encode_request/3, encode_response/2, encode_error_response/3,
         encode_notification/2, decode_message/1, create_error/3]).

%% Types
-type json_rpc_message() ::
    #json_rpc_request{} | #json_rpc_response{} | #json_rpc_notification{}.
-type decode_result() :: {ok, json_rpc_message()} | {error, {atom(), term()}}.

-export_type([json_rpc_message/0]).

%%====================================================================
%% API Functions
%%====================================================================

-spec encode_request(json_rpc_id(), binary(), json_rpc_params()) -> binary().
encode_request(Id, Method, Params) when is_binary(Method) ->
    Request =
        #json_rpc_request{id = Id,
                          method = Method,
                          params = Params},
    encode_message(Request).

-spec encode_response(json_rpc_id(), term()) -> binary().
encode_response(Id, Result) ->
    Response = #json_rpc_response{id = Id, result = Result},
    encode_message(Response).

-spec encode_error_response(json_rpc_id(), integer(), binary()) -> binary().
encode_error_response(Id, Code, Message) when is_integer(Code), is_binary(Message) ->
    Error = #{?JSONRPC_ERROR_FIELD_CODE => Code, ?JSONRPC_ERROR_FIELD_MESSAGE => Message},
    Response = #json_rpc_response{id = Id, error = Error},
    encode_message(Response).

-spec encode_notification(binary(), json_rpc_params()) -> binary().
encode_notification(Method, Params) when is_binary(Method) ->
    Notification = #json_rpc_notification{method = Method, params = Params},
    encode_message(Notification).

-spec decode_message(binary()) -> decode_result().
decode_message(Json) when is_binary(Json) ->
    case erlmcp_codec:decode(Json) of
        {ok, Data} when is_map(Data) ->
            parse_json_rpc(Data);
        {ok, _} ->
            {error, {invalid_json, not_object}};
        {error, _} ->
            {error, {parse_error, invalid_json}}
    end.

-spec create_error(integer(), binary(), term()) -> #mcp_error{}.
create_error(Code, Message, Data) when is_integer(Code), is_binary(Message) ->
    #mcp_error{code = Code,
               message = Message,
               data = Data}.

%%====================================================================
%% Internal Functions
%%====================================================================

-spec encode_message(json_rpc_message()) -> binary().
encode_message(Message) ->
    Map = build_message_map(Message),
    {ok, Bin} = erlmcp_codec:encode(Map),
    Bin.

-spec build_message_map(json_rpc_message()) -> map().
build_message_map(#json_rpc_request{id = Id,
                                    method = Method,
                                    params = Params}) ->
    Base =
        #{?JSONRPC_FIELD_JSONRPC => ?JSONRPC_VERSION,
          ?JSONRPC_FIELD_ID => encode_id(Id),
          ?JSONRPC_FIELD_METHOD => Method},
    maybe_add_params(Base, Params);
build_message_map(#json_rpc_response{id = Id,
                                     result = Result,
                                     error = Error}) ->
    Base = #{?JSONRPC_FIELD_JSONRPC => ?JSONRPC_VERSION, ?JSONRPC_FIELD_ID => encode_id(Id)},
    add_result_or_error(Base, Result, Error);
build_message_map(#json_rpc_notification{method = Method, params = Params}) ->
    Base = #{?JSONRPC_FIELD_JSONRPC => ?JSONRPC_VERSION, ?JSONRPC_FIELD_METHOD => Method},
    maybe_add_params(Base, Params).

-spec encode_id(json_rpc_id()) -> json_rpc_id().
encode_id(null) ->
    null;
encode_id(Id) when is_binary(Id) ->
    Id;
encode_id(Id) when is_integer(Id) ->
    Id.

-spec maybe_add_params(map(), json_rpc_params()) -> map().
maybe_add_params(Map, undefined) ->
    Map;
maybe_add_params(Map, Params) ->
    Map#{?JSONRPC_FIELD_PARAMS => Params}.

-spec add_result_or_error(map(), term(), map() | undefined) -> map().
add_result_or_error(Map, _Result, Error) when is_map(Error) ->
    Map#{?JSONRPC_FIELD_ERROR => Error};
add_result_or_error(Map, Result, undefined) ->
    Map#{?JSONRPC_FIELD_RESULT => Result}.

-spec parse_json_rpc(map()) -> decode_result().
parse_json_rpc(Data) ->
    case validate_jsonrpc_version(Data) of
        ok ->
            parse_by_type(Data);
        Error ->
            Error
    end.

-spec validate_jsonrpc_version(map()) -> ok | {error, {invalid_request, term()}}.
validate_jsonrpc_version(#{?JSONRPC_FIELD_JSONRPC := ?JSONRPC_VERSION}) ->
    ok;
validate_jsonrpc_version(#{?JSONRPC_FIELD_JSONRPC := Version}) ->
    {error, {invalid_request, {wrong_version, Version}}};
validate_jsonrpc_version(_) ->
    {error, {invalid_request, missing_jsonrpc}}.

-spec parse_by_type(map()) -> decode_result().
parse_by_type(#{?JSONRPC_FIELD_ID := Id, ?JSONRPC_FIELD_METHOD := Method} = Data) ->
    parse_request(Id, Method, Data);
parse_by_type(#{?JSONRPC_FIELD_ID := Id, ?JSONRPC_FIELD_RESULT := Result}) ->
    parse_response(Id, Result, undefined);
parse_by_type(#{?JSONRPC_FIELD_ID := Id, ?JSONRPC_FIELD_ERROR := Error}) ->
    parse_response(Id, undefined, Error);
parse_by_type(#{?JSONRPC_FIELD_METHOD := Method} = Data) ->
    parse_notification(Method, Data);
parse_by_type(_) ->
    {error, {invalid_request, unknown_message_type}}.

-spec parse_request(json_rpc_id(), binary(), map()) -> decode_result().
parse_request(Id, Method, Data) when is_binary(Method) ->
    Params = maps:get(?JSONRPC_FIELD_PARAMS, Data, undefined),
    {ok,
     #json_rpc_request{id = decode_id(Id),
                       method = Method,
                       params = validate_params(Params)}};
parse_request(_Id, Method, _Data) ->
    {error, {invalid_request, {invalid_method, Method}}}.

-spec parse_response(json_rpc_id(), term(), term()) -> decode_result().
parse_response(Id, Result, Error) ->
    {ok,
     #json_rpc_response{id = decode_id(Id),
                        result = Result,
                        error = Error}}.

-spec parse_notification(binary(), map()) -> decode_result().
parse_notification(Method, Data) when is_binary(Method) ->
    Params = maps:get(?JSONRPC_FIELD_PARAMS, Data, undefined),
    {ok, #json_rpc_notification{method = Method, params = validate_params(Params)}};
parse_notification(Method, _Data) ->
    {error, {invalid_request, {invalid_method, Method}}}.

-spec decode_id(term()) -> json_rpc_id().
decode_id(null) ->
    null;
decode_id(Id) when is_binary(Id) ->
    Id;
decode_id(Id) when is_integer(Id) ->
    Id;
decode_id(Id) ->
    Id.  % Be lenient with ID format

-spec validate_params(term()) -> json_rpc_params().
validate_params(undefined) ->
    undefined;
validate_params(Params) when is_map(Params) ->
    Params;
validate_params(Params) when is_list(Params) ->
    Params;
validate_params(_) ->
    undefined.  % Invalid params become undefined
