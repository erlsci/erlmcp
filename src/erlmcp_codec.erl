-module(erlmcp_codec).

-include_lib("kernel/include/logger.hrl").

-export([encode/1, decode/1, ensure_utf8/1,
         validate_outbound/1]).

-spec encode(term()) -> {ok, binary()} | {error, term()}.
encode(Term) ->
    try
        Json = jsx:encode(Term),
        case ensure_utf8(Json) of
            ok -> {ok, Json};
            {error, _} = Err -> Err
        end
    catch
        error:badarg -> {error, {encode_error, badarg}}
    end.

-spec decode(binary()) -> {ok, term()} | {error, term()}.
decode(Bin) when is_binary(Bin) ->
    try
        {ok, jsx:decode(Bin, [return_maps])}
    catch
        error:badarg -> {error, {decode_error, badarg}}
    end;
decode(_) ->
    {error, {decode_error, not_binary}}.

-spec ensure_utf8(binary()) -> ok | {error, invalid_utf8}.
ensure_utf8(Bin) when is_binary(Bin) ->
    case unicode:characters_to_binary(Bin, utf8) of
        Bin -> ok;
        _ -> {error, invalid_utf8}
    end;
ensure_utf8(_) ->
    {error, invalid_utf8}.

-spec validate_outbound(term()) -> ok | {error, term()}.
validate_outbound(Term) when is_map(Term) ->
    case classify_outbound(Term) of
        {response, _Id, Result} ->
            validate_outbound_result(Result);
        {error_response, _Id, Error} ->
            validate_outbound_error(Error);
        {notification, _Method, _Params} ->
            ok;
        unknown ->
            ok
    end;
validate_outbound(_) ->
    ok.

%%====================================================================
%% Internal — outbound validation
%%====================================================================

classify_outbound(Map) ->
    case maps:find(<<"result">>, Map) of
        {ok, Result} ->
            {response, maps:get(<<"id">>, Map, null), Result};
        error ->
            case maps:find(<<"error">>, Map) of
                {ok, Error} ->
                    {error_response, maps:get(<<"id">>, Map, null), Error};
                error ->
                    case maps:find(<<"method">>, Map) of
                        {ok, Method} ->
                            {notification, Method, maps:get(<<"params">>, Map, #{})};
                        error ->
                            unknown
                    end
            end
    end.

validate_outbound_result(Result) when is_map(Result) ->
    case maps:find(<<"tools">>, Result) of
        {ok, Tools} when is_list(Tools) ->
            validate_tools_list(Tools);
        _ ->
            ok
    end;
validate_outbound_result(_) ->
    ok.

validate_outbound_error(Error) when is_map(Error) ->
    erlmcp_schema:validate_protocol(<<"Error">>, Error);
validate_outbound_error(_) ->
    ok.

validate_tools_list(Tools) ->
    case erlmcp_schema:protocol_definition(<<"ListToolsResult">>) of
        {ok, Schema} ->
            erlmcp_schema:validate(Schema, #{<<"tools">> => Tools});
        {error, _} ->
            ok
    end.
