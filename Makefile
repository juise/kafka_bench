.PHONY: all compile run clean

REBAR=./rebar3

all: $(REBAR) compile

compile:
		$(REBAR) compile

run:
		erl -pa _build/default/lib/*/ebin -config config/sys.config -args_file config/vm.args -boot start_sasl -s sync -s kafka_bench

clean:
		$(REBAR) clean
		rm -rf ./log
		rm -rf ./erl_crash.dump

