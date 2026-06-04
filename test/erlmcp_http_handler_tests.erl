-module(erlmcp_http_handler_tests).

-include_lib("eunit/include/eunit.hrl").

classify_message_test_() ->
    [{"request has id and method",
      fun() ->
          Req = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
          ?assertEqual(request, classify(Req))
      end},
     {"notification has no id",
      fun() ->
          Notif = erlmcp_json_rpc:encode_notification(
              <<"notifications/initialized">>, #{}),
          ?assertEqual(fire_and_forget, classify(Notif))
      end},
     {"response has id but no method",
      fun() ->
          Resp = erlmcp_json_rpc:encode_response(1, #{<<"content">> => <<"x">>}),
          ?assertEqual(fire_and_forget, classify(Resp))
      end},
     {"garbage treated as request",
      fun() ->
          ?assertEqual(request, classify(<<"not json">>))
      end}].

classify(Body) ->
    case erlmcp_codec:decode(Body) of
        {ok, Map} when is_map(Map) ->
            HasId = maps:is_key(<<"id">>, Map),
            HasMethod = maps:is_key(<<"method">>, Map),
            case {HasId, HasMethod} of
                {false, _} -> fire_and_forget;
                {true, false} -> fire_and_forget;
                {true, true} -> request
            end;
        _ ->
            request
    end.
