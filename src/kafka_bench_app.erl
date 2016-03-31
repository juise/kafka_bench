-module(kafka_bench_app).

-behaviour(application).

%% Application callbacks
-export([start/2,
         stop/1]).

%%====================================================================
%% API
%%====================================================================

-spec start(any(), any()) -> no_return().
start(_StartType, _StartArgs) ->
    kafka_bench_sup:start_link().

stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

