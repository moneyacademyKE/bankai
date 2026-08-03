# bankai build helpers.
# gleam/erl/rebar3 live in /opt/homebrew/bin which is off the stripped shell PATH,
# so every invocation re-exports it. Invoke targets with: make build / make test.
export PATH := /opt/homebrew/bin:$(PATH)

.PHONY: build test run deps clean

build:
	gleam build

test:
	gleam test

deps:
	gleam deps

clean:
	rm -rf build erl
