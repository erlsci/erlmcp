.PHONY: all compile compile-examples clean test dialyzer xref format lint docs console release docker check

REBAR := rebar3
APP_NAME := erlmcp
APP_VERSION := $(shell grep vsn src/$(APP_NAME).app.src | cut -d'"' -f2)

all: compile

compile:
	@$(REBAR) compile

# Compile the bundled example servers (their own rebar3 profiles).
# CI compiles these; keeping it here means `make check` catches example
# breakage (e.g. examples referencing changed core API) before a push.
compile-examples:
	@$(REBAR) as simple compile
	@$(REBAR) as calculator compile
	@$(REBAR) as weather compile

clean:
	@$(REBAR) cleanplus
	@rm -rf _build logs erl_crash.dump

# eunit/ct/proper run in the `test` profile and write coverdata to
# _build/test/cover; the cover gate MUST run `as test` to read that same
# coverdata (bare `rebar3 cover` runs in the default profile). Flags here
# match CI exactly so local and CI never diverge.
test:
	@mkdir -p logs
	@$(REBAR) eunit -v
	@$(REBAR) ct -v
	@$(REBAR) proper -c
	@$(REBAR) as test cover -v --min_coverage=90

# Dialyzer's opaque-type analysis is only reliable on OTP 27+; OTP 25/26 emit
# known false positives on opaque pid() aliases. Gate the type check to 27+ so
# it runs where it's trustworthy, while compile/xref/test still cover the full
# 25–28 matrix. The OTP version is detected at run time, so this one target
# governs both local `make check` and CI (which calls `make dialyzer`) — no CI
# matrix split needed, local and CI stay identical.
dialyzer:
	@otp=$$(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' 2>/dev/null); \
	if [ "$$otp" -ge 27 ] 2>/dev/null; then \
		$(REBAR) dialyzer; \
	else \
		echo "dialyzer: skipped on OTP $$otp (gated to 27+; 25/26 have opaque false positives)"; \
	fi

xref:
	@$(REBAR) xref

format:
	@$(REBAR) format

lint:
	@$(MAKE) xref dialyzer

console:
	@$(REBAR) shell

release:
	@$(REBAR) as prod release

# The single source of truth for "is the build green?". CI runs these same
# targets (see .github/workflows/ci.yml) across the OTP 25–28 matrix, so a
# green `make check` locally should mean a green CI. Keep this target and the
# CI job's target list in sync.
check: clean compile xref compile-examples dialyzer test
	@echo "All checks passed!"

# Development helpers
dev-console:
	@ERL_FLAGS="-config config/sys.config -args_file config/vm.args" $(REBAR) as dev shell

observer:
	@erl -name debug@127.0.0.1 -setcookie erlmcp_secret_cookie -run observer

# Testing helpers
test-client:
	@$(REBAR) shell --eval "simple_client:run()."

test-server:
	@$(REBAR) shell --eval "simple_server:start()."

test-advanced-client:
	@$(REBAR) shell --eval "simple_client:run_advanced()."

# Schema drift-guard: verify the protocol version in the hand-curated JSON
# Schema matches the version declared in schema.ts. Catches the case where
# schema.ts is bumped to a new protocol version without updating the JSON Schema.
schema-check:
	@TS_VER=$$(grep 'LATEST_PROTOCOL_VERSION' docs/0.6.0/planning/schema.ts | grep -oE '"[0-9]{4}-[0-9]{2}-[0-9]{2}"' | tr -d '"'); \
	JSON_VER=$$(grep '"title"' priv/schema/mcp-2025-11-25.json | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}'); \
	if [ "$$TS_VER" != "$$JSON_VER" ]; then \
		echo "SCHEMA DRIFT: schema.ts declares $$TS_VER but JSON Schema declares $$JSON_VER"; \
		exit 1; \
	fi; \
	echo "Schema version match: $$TS_VER"

# Coverage report
coverage-report:
	@$(REBAR) cover
	@echo "Coverage report generated in _build/test/cover/index.html"

# Performance profiling
profile:
	@$(REBAR) as dev shell --eval "recon_trace:calls({erlmcp_client, '_', '_'}, 100)."

# Docker support
docker-build:
	docker build -t $(APP_NAME):$(APP_VERSION) .

docker-run:
	docker run -it --rm $(APP_NAME):$(APP_VERSION)

# Installation
install: compile
	@echo "Installing $(APP_NAME)..."
	@$(REBAR) do compile, escriptize

# Create logs directory
init:
	@mkdir -p logs priv/ssl config
	@echo "Project initialized"

# Run specific test suites
test-unit:
	@$(REBAR) eunit

test-integration:
	@$(REBAR) ct

test-property:
	@$(REBAR) proper -c

test-local:
	@rm -rf _build/testlocal+test
	@$(REBAR) as testlocal eunit -v

# Static analysis
analyze: xref dialyzer lint
	@echo "Static analysis complete"

# Clean everything including deps
distclean: clean
	@rm -rf _build
	@echo "Deep clean complete"

publish:
	@echo "Publishing $(APP_NAME) v$(APP_VERSION)..."
	@$(REBAR) hex publish package

# Help
help:
	@echo "$(APP_NAME) v$(APP_VERSION) - Available targets:"
	@echo "  make compile       - Compile the project"
	@echo "  make test         - Run all tests"
	@echo "  make dialyzer     - Run Dialyzer"
	@echo "  make xref         - Run xref analysis"
	@echo "  make format       - Format code"
	@echo "  make lint         - Run linter"
	@echo "  make console      - Start Erlang shell with app loaded"
	@echo "  make release      - Build production release"
	@echo "  make check        - Run all checks (xref, dialyzer, tests)"
	@echo "  make coverage-report - Generate coverage report"
	@echo "  make publish	   - Publish to Hex"
	@echo "  make help         - Show this help message"
