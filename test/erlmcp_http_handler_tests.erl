-module(erlmcp_http_handler_tests).

-include_lib("eunit/include/eunit.hrl").

is_notification_test_() ->
    [{"request is not notification",
      fun() ->
          Req = erlmcp_json_rpc:encode_request(1, <<"ping">>, #{}),
          ?assertNot(is_notification(Req))
      end},
     {"notification is notification",
      fun() ->
          Notif = erlmcp_json_rpc:encode_notification(
              <<"notifications/initialized">>, #{}),
          ?assert(is_notification(Notif))
      end},
     {"garbage is not notification",
      fun() ->
          ?assertNot(is_notification(<<"not json">>))
      end}].

is_notification(Body) ->
    case erlmcp_codec:decode(Body) of
        {ok, Map} when is_map(Map) ->
            not maps:is_key(<<"id">>, Map);
        _ ->
            false
    end.
