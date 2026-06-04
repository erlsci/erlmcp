-module(erlmcp_http_sse).

-opaque buffer() :: #{
    next_id := non_neg_integer(),
    max_size := pos_integer(),
    events := queue:queue({non_neg_integer(), iodata()})
}.

-export_type([buffer/0]).

-export([new_buffer/0, new_buffer/1,
         push_event/2, format_event/2,
         replay_from/2, next_id/1, size/1]).

-define(DEFAULT_MAX_SIZE, 100).

-spec new_buffer() -> buffer().
new_buffer() ->
    new_buffer(?DEFAULT_MAX_SIZE).

-spec new_buffer(pos_integer()) -> buffer().
new_buffer(MaxSize) when is_integer(MaxSize), MaxSize > 0 ->
    #{next_id => 0, max_size => MaxSize, events => queue:new()}.

-spec push_event(buffer(), iodata()) -> {non_neg_integer(), iodata(), buffer()}.
push_event(#{next_id := Id, max_size := Max, events := Q} = Buf, Data) ->
    Formatted = format_event(Id, Data),
    Q1 = queue:in({Id, Data}, Q),
    Q2 = case queue:len(Q1) > Max of
        true -> element(2, queue:out(Q1));
        false -> Q1
    end,
    {Id, Formatted, Buf#{next_id := Id + 1, events := Q2}}.

-spec format_event(non_neg_integer(), iodata()) -> [binary() | iodata()].
format_event(Id, Data) ->
    [<<"id: ">>, integer_to_binary(Id), <<"\ndata: ">>, Data, <<"\n\n">>].

-spec replay_from(buffer(), non_neg_integer()) -> [iodata()].
replay_from(#{events := Q}, LastEventId) ->
    lists:filtermap(fun({Id, Data}) ->
        case Id > LastEventId of
            true -> {true, format_event(Id, Data)};
            false -> false
        end
    end, queue:to_list(Q)).

-spec next_id(buffer()) -> non_neg_integer().
next_id(#{next_id := Id}) -> Id.

-spec size(buffer()) -> non_neg_integer().
size(#{events := Q}) -> queue:len(Q).
