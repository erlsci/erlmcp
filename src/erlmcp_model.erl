-module(erlmcp_model).

%% Opaque MCP types with constructors and accessors.
%% Records are private to this module; they never cross a boundary.

-export([
    %% JSON-RPC envelope
    make_request/3,
    make_response/2,
    make_error_response/2,
    make_notification/2,
    request_id/1,
    request_method/1,
    request_params/1,
    response_id/1,
    response_result/1,
    response_error/1,
    is_error_response/1,
    notification_method/1,
    notification_params/1,
    %% Error
    make_error/3,
    error_code/1,
    error_message/1,
    error_data/1,
    %% Capabilities
    make_capabilities/1,
    has_capability/2,
    capabilities_to_map/1,
    %% Protocol info
    make_server_info/2,
    make_client_info/2,
    info_name/1,
    info_version/1
]).

-export_type([
    request/0,
    response/0,
    notification/0,
    rpc_id/0,
    rpc_error/0,
    capabilities/0,
    peer_info/0
]).

-opaque request() :: #{
    id := rpc_id(),
    method := binary(),
    params := map() | undefined
}.

-opaque response() :: #{
    id := rpc_id(),
    result := term(),
    error := rpc_error() | undefined
}.

-opaque notification() :: #{
    method := binary(),
    params := map() | undefined
}.

-opaque rpc_error() :: #{
    code := integer(),
    message := binary(),
    data := term()
}.

-opaque capabilities() :: #{binary() => map()}.

-opaque peer_info() :: #{
    name := binary(),
    version := binary()
}.

-type rpc_id() :: integer() | binary() | null.

%%====================================================================
%% JSON-RPC envelope constructors
%%====================================================================

-spec make_request(rpc_id(), binary(), map() | undefined) -> request().
make_request(Id, Method, Params) when is_binary(Method) ->
    #{id => Id, method => Method, params => Params}.

-spec make_response(rpc_id(), term()) -> response().
make_response(Id, Result) ->
    #{id => Id, result => Result, error => undefined}.

-spec make_error_response(rpc_id(), rpc_error()) -> response().
make_error_response(Id, Error) ->
    #{id => Id, result => undefined, error => Error}.

-spec make_notification(binary(), map() | undefined) -> notification().
make_notification(Method, Params) when is_binary(Method) ->
    #{method => Method, params => Params}.

%%====================================================================
%% JSON-RPC envelope accessors
%%====================================================================

-spec request_id(request()) -> rpc_id().
request_id(#{id := Id}) -> Id.

-spec request_method(request()) -> binary().
request_method(#{method := Method}) -> Method.

-spec request_params(request()) -> map() | undefined.
request_params(#{params := Params}) -> Params.

-spec response_id(response()) -> rpc_id().
response_id(#{id := Id}) -> Id.

-spec response_result(response()) -> term().
response_result(#{result := Result}) -> Result.

-spec response_error(response()) -> rpc_error() | undefined.
response_error(#{error := Error}) -> Error.

-spec is_error_response(response()) -> boolean().
is_error_response(#{error := undefined}) -> false;
is_error_response(#{error := _}) -> true.

-spec notification_method(notification()) -> binary().
notification_method(#{method := Method}) -> Method.

-spec notification_params(notification()) -> map() | undefined.
notification_params(#{params := Params}) -> Params.

%%====================================================================
%% Error constructors/accessors
%%====================================================================

-spec make_error(integer(), binary(), term()) -> rpc_error().
make_error(Code, Message, Data) when is_integer(Code), is_binary(Message) ->
    #{code => Code, message => Message, data => Data}.

-spec error_code(rpc_error()) -> integer().
error_code(#{code := Code}) -> Code.

-spec error_message(rpc_error()) -> binary().
error_message(#{message := Msg}) -> Msg.

-spec error_data(rpc_error()) -> term().
error_data(#{data := Data}) -> Data.

%%====================================================================
%% Capabilities
%%====================================================================

-spec make_capabilities(#{binary() => map()}) -> capabilities().
make_capabilities(Map) when is_map(Map) -> Map.

-spec has_capability(capabilities(), binary()) -> boolean().
has_capability(Caps, Name) when is_binary(Name) ->
    maps:is_key(Name, Caps).

-spec capabilities_to_map(capabilities()) -> #{binary() => map()}.
capabilities_to_map(Caps) -> Caps.

%%====================================================================
%% Peer info
%%====================================================================

-spec make_server_info(binary(), binary()) -> peer_info().
make_server_info(Name, Version) when is_binary(Name), is_binary(Version) ->
    #{name => Name, version => Version}.

-spec make_client_info(binary(), binary()) -> peer_info().
make_client_info(Name, Version) when is_binary(Name), is_binary(Version) ->
    #{name => Name, version => Version}.

-spec info_name(peer_info()) -> binary().
info_name(#{name := Name}) -> Name.

-spec info_version(peer_info()) -> binary().
info_version(#{version := Version}) -> Version.
