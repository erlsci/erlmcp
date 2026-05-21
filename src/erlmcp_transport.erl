-module(erlmcp_transport).

%% Transport behaviour definition (Phase 2 §6).
%% Each transport is a gen_server implementing these callbacks.
%% Inbound data is delivered directly to the bound session process.

-type transport_id() :: atom().
-type config() :: map().
-type state() :: term().

-type transport_message() ::
      {transport_data, binary()}
    | {transport_connected, map()}
    | {transport_disconnected, term()}
    | {transport_error, atom(), term()}.

%% Core callbacks
-callback init(TransportId :: transport_id(), Config :: config()) ->
    {ok, state()} | {error, term()}.

-callback send(state(), iodata()) ->
    ok | {error, term()}.

-callback close(state()) -> ok.

%% Optional callbacks for richer transports
-callback get_info(state()) ->
    #{type => atom(), status => atom(), peer => term()}.

-callback handle_transport_call(Request :: term(), state()) ->
    {reply, term(), state()} | {error, term()}.

-optional_callbacks([get_info/1, handle_transport_call/2]).

-export_type([transport_id/0, config/0, state/0, transport_message/0]).
