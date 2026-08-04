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

# escript: bundle every compiled .beam/.app into a single self-contained
# executable via `gleam export escript` (prod build → zip archive with the
# `%%!-escript main bankai@@main` header). The result runs on any machine with
# Erlang/OTP installed — copy the one file, no source tree, no per-run gleam
# rebuild. bankai's honest tradeoff vs beads's static Go binary: the target
# needs a BEAM runtime. (The root ./bankai dev-wrapper was removed to free the
# `gleam export escript` output path; use `gleam run -m bankai -- <cmd>` for
# source-tree development.)
escript:
	gleam export escript
	@mkdir -p dist
	@mv -f bankai dist/bankai
	@echo "Built ./dist/bankai (self-contained escript; requires Erlang/OTP)"
