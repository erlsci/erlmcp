-module(erlmcp_transport).

%% Transport behaviour definition (Phase 6 §3.4).
%%
%% A transport delivers framed inbound messages with their responder to a
%% session, and accepts outbound via the responder. The lifecycle is:
%%   init(Config) -> serve(State) -> close(State)
%%
%% Inbound contract: the transport delivers
%%   {transport_data, binary(), erlmcp_reply:responder()}
%% to its bound session. The session never calls back into the transport
%% for outbound — it sends through the responder.

-type config() :: map().
-type state() :: term().

%% Lifecycle callbacks
-callback init(Config :: config()) ->
    {ok, state()} | {error, term()}.

-callback serve(state()) ->
    {ok, state()} | {error, term()}.

-callback close(state()) -> ok.

%% Optional: metadata about the transport
-callback get_info(state()) ->
    #{type => atom(), status => atom(), peer => term()}.

-optional_callbacks([get_info/1]).

-export_type([config/0, state/0]).
