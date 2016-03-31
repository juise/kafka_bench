# kafka_bench

kafka_bench:producer_perf([{"broker1", 9092}, {"broker2", 9092}, {"broker3", 9092}], <<"test-topic-p1-rf1">>, _Count = 100000, _Size = 512).
kafka_bench:consumer_perf([{"broker1", 9092}, {"broker2", 9092}, {"broker3", 9092}], <<"test-topic-p7-rf1">>, _Count = 100000, _Size = 512).

