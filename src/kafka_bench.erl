-module(kafka_bench).

%% API
-export([start/0]).

-export([start_producer/2,
         start_consumer/2,
         stop_producer/2,
         stop_consumer/2]).

-export([publish/4]).

-export([init/2,
         handle_message/4]).

-export([producer_perf/4,
         consumer_perf/4]).

-include_lib("brod/include/brod.hrl").

-record(state, {count               :: integer(),
                rev_count           :: non_neg_integer(),
                start_time          :: erlang:timestamp(),
                bootstrap_hosts     :: list()
}).

%%====================================================================
%% API functions
%%====================================================================

start() ->
    {ok, _} = application:ensure_all_started(kafka_bench),
    ok.


partitions(BootstrapHosts, Topic) ->
    case brod:start_link_client(BootstrapHosts, sys_info_client, []) of
        {ok, _ClientPid} ->
            ok;
        {error, {already_started, _ClientPid}} ->
            ok
    end,
    {ok, Partitions} = brod:get_partitions_count(sys_info_client, Topic),
    Partitions.

start_producer(BootstrapHosts, Topic) ->
    Partitions = partitions(BootstrapHosts, Topic),
    stop_producer(BootstrapHosts, Topic),
    [start_producer_ll(BootstrapHosts, Topic, N) || N <- lists:seq(0, Partitions - 1)].

start_consumer(BootstrapHosts, Topic) ->
    start_consumer(BootstrapHosts, Topic, -1).

start_consumer(BootstrapHosts, Topic, Count) ->
    Partitions = partitions(BootstrapHosts, Topic),
    stop_consumer(BootstrapHosts, Topic),
    [start_consumer_ll(BootstrapHosts, Topic, N, Count) || N <- lists:seq(0, Partitions - 1)].

stop_producer(BootstrapHosts, Topic) ->
    Partitions = partitions(BootstrapHosts, Topic),
    [stop_producer_ll(Topic, N) || N <- lists:seq(0, Partitions - 1)].

stop_consumer(BootstrapHosts, Topic) ->
    Partitions = partitions(BootstrapHosts, Topic),
    [stop_consumer_ll(Topic, N) || N <- lists:seq(0, Partitions - 1)].


publish(ProducerId, Topic, Partition, Msg) ->
    ok = brod:produce_sync(ProducerId, Topic, Partition, <<>>, Msg).


init(ConsumerGroupId, State) ->
    {ok, State}.

handle_message(_Topic, Partition, #kafka_message{offset = Offset, value = Value} = Message, #state{count = -1} = State) ->
    lager:info("Offset:~p, Message:~p", [Offset, Value]),
    {ok, ack, State};

handle_message(Topic, _Partition, #kafka_message{offset = Offset, value = Value} = Message, #state{count = Count, rev_count = Count} = State) ->
    {ok, ack, State#state{rev_count = Count - 1, start_time = os:timestamp()}};

handle_message(Topic, _Partition, #kafka_message{offset = Offset, value = Value} = Message, #state{count = Count, rev_count = 1, start_time = StartTime, bootstrap_hosts = BootstrapHosts} = State) ->
    StopTime = os:timestamp(),
    lager:info("Counsumer: ~p packets, ~p ms", [Count, timer:now_diff(StopTime, StartTime) / 1000]),
    {ok, ack, State#state{rev_count = 0}};

handle_message(_Topic, _Partition, #kafka_message{offset = Offset, value = Value} = Message, #state{rev_count = RevCount} = State) ->
    {ok, ack, State#state{rev_count = RevCount - 1}}.

producer_perf(BootstrapHosts, Topic, Count, Size) when is_integer(Size) ->
    Message = list_to_binary(lists:duplicate(Size, 1)),
    producer_perf(BootstrapHosts, Topic, Count, Message);

producer_perf(BootstrapHosts, Topic, Count, Message) ->
    Producers = start_producer(BootstrapHosts, Topic),
    Iterations = lists:seq(0, Count div length(Producers)),
    StartTime = os:timestamp(),
    ok = prun(Iterations, Producers, fun({Partition, ProducerId}) -> ok = brod:produce_sync(ProducerId, Topic, Partition, <<>>, Message) end),
    StopTime = os:timestamp(),
    lager:info("Producer: ~p packets, ~p ms", [Count, timer:now_diff(StopTime, StartTime) / 1000]),
    ok.

consumer_perf(BootstrapHosts, Topic, Count, Size) ->
    _Consumers = start_consumer(BootstrapHosts, Topic, Count),
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

start_producer_ll(BootstrapHosts, Topic, N) ->
    ProducerId = binary_to_atom(<<"producer-", (integer_to_binary(N))/binary, "-", Topic/binary>>, utf8),
    {ok, _ClientPid} = brod:start_link_client(BootstrapHosts, ProducerId, []),
    ok = brod:start_producer(ProducerId, Topic, []),
    {N, ProducerId}.

start_consumer_ll(BootstrapHosts, Topic, N, Count) ->
    ConsumerGroupId = <<"consumer-group-", Topic/binary>>,
    ConsumerGroupConfig = [{offset_commit_policy, commit_to_kafka_v2}, {offset_commit_interval_seconds, 1}],
    ConsumerId = binary_to_atom(<<"consumer-", (integer_to_binary(N))/binary, "-", Topic/binary>>, utf8),
    ConsumerConfig = [{begin_offset, -2}],
    {ok, _ClientPid} = brod:start_link_client(BootstrapHosts, ConsumerId, []),
    {ok, _Subscriber} = brod_group_subscriber:start_link(ConsumerId, ConsumerGroupId, [Topic], ConsumerGroupConfig, ConsumerConfig, ?MODULE, #state{count = Count,
                                                                                                                                                    rev_count = Count,
                                                                                                                                                    start_time = os:timestamp(),
                                                                                                                                                    bootstrap_hosts = BootstrapHosts}),
    {N, ConsumerId}.

stop_producer_ll(Topic, N) ->
    ProducerId = binary_to_atom(<<"producer-", (integer_to_binary(N))/binary, "-", Topic/binary>>, utf8),
    brod:stop_client(ProducerId).

stop_consumer_ll(Topic, N) ->
    ConsumerId = binary_to_atom(<<"consumer-", (integer_to_binary(N))/binary, "-", Topic/binary>>, utf8),
    brod:stop_client(ConsumerId).


prun(Iterations, Producers, F) ->
    Self = self(),
    collect(length([spawn(fun() -> [F(Producer) || _ <- Iterations], Self ! done end) || Producer <- Producers])).

collect(0) ->
    ok;

collect(N) ->
    receive
        done ->
            collect(N - 1)
    end.

