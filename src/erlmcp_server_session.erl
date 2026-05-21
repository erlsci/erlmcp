-module(erlmcp_server_session).

-behaviour(gen_statem).

-export([start_link/1]).
-export([callback_mode/0, init/1, terminate/3]).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) when is_map(Opts) ->
    gen_statem:start_link(?MODULE, Opts, []).

-spec callback_mode() -> [gen_statem:callback_mode()].
callback_mode() ->
    [state_functions, state_enter].

-spec init(map()) -> gen_statem:init_result(atom()).
init(_Opts) ->
    {ok, uninitialized, #{}}.

-spec terminate(term(), atom(), term()) -> ok.
terminate(_Reason, _State, _Data) ->
    ok.
