-module(erlmcp_reply).

-opaque responder() :: {device, pid()}.

-export_type([responder/0]).

-export([new_device/1, send/2]).

-spec new_device(pid()) -> responder().
new_device(Pid) when is_pid(Pid) ->
    {device, Pid}.

-spec send(responder(), iodata()) -> ok.
send({device, Pid}, Json) ->
    Pid ! {send, Json},
    ok.
