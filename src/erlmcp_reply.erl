-module(erlmcp_reply).

-opaque responder() :: {device, pid()}
                      | {http, pid(), reference()}
                      | {sse, pid()}.

-export_type([responder/0]).

-export([new_device/1, new_http/2, new_sse/1, send/2]).

-spec new_device(pid()) -> responder().
new_device(Pid) when is_pid(Pid) ->
    {device, Pid}.

-spec new_http(pid(), reference()) -> responder().
new_http(ConnPid, ReqRef) when is_pid(ConnPid), is_reference(ReqRef) ->
    {http, ConnPid, ReqRef}.

-spec new_sse(pid()) -> responder().
new_sse(StreamPid) when is_pid(StreamPid) ->
    {sse, StreamPid}.

-spec send(responder(), iodata()) -> ok.
send({device, Pid}, Json) ->
    Pid ! {send, Json},
    ok;
send({http, ConnPid, ReqRef}, Json) ->
    ConnPid ! {jsonrpc_out, ReqRef, Json},
    ok;
send({sse, StreamPid}, Json) ->
    StreamPid ! {sse_event, Json},
    ok.
