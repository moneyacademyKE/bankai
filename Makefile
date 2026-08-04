# bankai build helpers.
# gleam/erl/rebar3 live in /opt/homebrew/bin which is off the stripped shell PATH,
# so every invocation re-exports it. Invoke targets with: make build / make test.
export PATH := /opt/homebrew/bin:$(PATH)

.PHONY: build test run deps clean escript

build:
	gleam build

test:
	gleam test

deps:
	gleam deps

clean:
	rm -rf build erl dist

# escript: produce ./dist/bankai, a runnable wrapper over the compiled BEAM
# modules (invokes `erl` directly — no per-run gleam rebuild, no daemon). The
# wrapper bakes the absolute -pa path to this tree's compiled ebin at build
# time, so the installed `bankai` needs Erlang/OTP and this built source tree
# present: bankai's honest tradeoff vs beads's single static Go binary. A
# fully portable bundled-.beam archive is a later distribution step.
escript:
	gleam build --target erlang
	@mkdir -p dist
	@printf '#!/bin/sh\nexport PATH="/opt/homebrew/bin:$$PATH"\nexec erl -noshell -pa %s/build/dev/erlang/*/ebin -s bankai main -s init stop -- "$$@"\n' "$(CURDIR)" > dist/bankai
	@chmod +x dist/bankai
	@echo "Built ./dist/bankai (requires Erlang/OTP + this built source tree)"
