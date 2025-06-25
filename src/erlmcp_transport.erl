-module(erlmcp_transport).

%% Transport behavior definition

-type transport_state() :: term().
-type transport_opts() :: term().

%% Callback definitions
-callback init(Opts :: transport_opts()) -> 
    {ok, State :: transport_state()} | 
    {error, Reason :: term()}.

-callback send(State :: transport_state(), Data :: iodata()) -> 
    ok | 
    {error, Reason :: term()}.

-callback close(State :: transport_state()) -> 
    ok.

%% Optional callbacks
-optional_callbacks([close/1]).

%% Type exports
-export_type([transport_state/0, transport_opts/0]).