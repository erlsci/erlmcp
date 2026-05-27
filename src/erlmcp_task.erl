-module(erlmcp_task).

-behaviour(gen_server).

-export([start_link/1, get_status/1, get_result/1, cancel/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    id :: binary(),
    session :: pid(),
    handler :: fun(),
    args :: map(),
    ctx :: erlmcp_ctx:ctx(),
    status = running :: running | completed | failed | cancelled,
    progress = 0.0 :: float(),
    progress_message = <<>> :: binary(),
    result :: term(),
    worker :: {pid(), reference()} | undefined
}).

-spec start_link(map()) -> gen_server:start_ret().
start_link(Opts) when is_map(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

-spec get_status(pid()) -> {ok, map()}.
get_status(Pid) ->
    gen_server:call(Pid, get_status).

-spec get_result(pid()) -> {ok, term()} | {error, not_ready | cancelled | {failed, term()}}.
get_result(Pid) ->
    gen_server:call(Pid, get_result).

-spec cancel(pid()) -> ok.
cancel(Pid) ->
    gen_server:call(Pid, cancel).

init(Opts) ->
    Id = maps:get(id, Opts),
    Session = maps:get(session, Opts),
    Handler = maps:get(handler, Opts),
    Args = maps:get(args, Opts, #{}),
    Ctx = maps:get(ctx, Opts),
    State = #state{
        id = Id,
        session = Session,
        handler = Handler,
        args = Args,
        ctx = Ctx
    },
    self() ! run,
    {ok, State}.

handle_call(get_status, _From, State) ->
    Status = #{
        <<"id">> => State#state.id,
        <<"status">> => atom_to_binary(State#state.status, utf8),
        <<"progress">> => State#state.progress,
        <<"message">> => State#state.progress_message
    },
    {reply, {ok, Status}, State};

handle_call(get_result, _From, #state{status = completed, result = Result} = State) ->
    {reply, {ok, Result}, State};
handle_call(get_result, _From, #state{status = failed, result = Reason} = State) ->
    {reply, {error, {failed, Reason}}, State};
handle_call(get_result, _From, #state{status = cancelled} = State) ->
    {reply, {error, cancelled}, State};
handle_call(get_result, _From, State) ->
    {reply, {error, not_ready}, State};

handle_call(cancel, _From, #state{status = running, worker = {Pid, Ref}} = State) ->
    demonitor(Ref, [flush]),
    exit(Pid, cancelled),
    {reply, ok, State#state{status = cancelled, worker = undefined}};
handle_call(cancel, _From, #state{status = running} = State) ->
    {reply, ok, State#state{status = cancelled}};
handle_call(cancel, _From, State) ->
    {reply, ok, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({progress, Fraction, Message}, State) ->
    NewState = State#state{progress = Fraction, progress_message = Message},
    send_progress_notification(NewState),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(run, #state{status = running} = State) ->
    TaskPid = self(),
    {Pid, Ref} = spawn_monitor(fun() ->
        Result = run_handler(State#state.handler, State#state.args,
                             State#state.ctx, TaskPid),
        TaskPid ! {task_result, Result}
    end),
    {noreply, State#state{worker = {Pid, Ref}}};

handle_info({task_result, {ok, Result}}, State) ->
    cleanup_worker(State),
    {noreply, State#state{status = completed, result = Result,
                          worker = undefined, progress = 1.0}};

handle_info({task_result, {error, Code, Msg}}, State) ->
    cleanup_worker(State),
    {noreply, State#state{status = failed, result = {Code, Msg},
                          worker = undefined}};

handle_info({'DOWN', _Ref, process, _Pid, normal}, State) ->
    {noreply, State};
handle_info({'DOWN', _Ref, process, _Pid, cancelled}, State) ->
    {noreply, State#state{status = cancelled, worker = undefined}};
handle_info({'DOWN', _Ref, process, _Pid, Reason}, State) ->
    {noreply, State#state{status = failed, result = Reason, worker = undefined}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{worker = {Pid, Ref}}) ->
    demonitor(Ref, [flush]),
    exit(Pid, shutdown),
    ok;
terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal
%%====================================================================

run_handler(Handler, Args, Ctx, TaskPid) when is_function(Handler, 3) ->
    Handler(Args, Ctx, TaskPid);
run_handler(Handler, Args, Ctx, _TaskPid) when is_function(Handler, 2) ->
    Handler(Args, Ctx).

cleanup_worker(#state{worker = {_Pid, Ref}}) ->
    demonitor(Ref, [flush]);
cleanup_worker(_) ->
    ok.

send_progress_notification(#state{ctx = Ctx, progress = Fraction,
                                   progress_message = Msg}) ->
    erlmcp_ctx:report_progress(Ctx, Fraction, Msg).
