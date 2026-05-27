.PHONY: all compile clean test dialyzer xref format lint docs console release docker check

REBAR := rebar3
APP_NAME := erlmcp
APP_VERSION := $(shell grep vsn src/$(APP_NAME).app.src | cut -d'"' -f2)

all: compile

compile:
	@$(REBAR) compile

clean:
	@$(REBAR) cleanplus
	@rm -rf _build logs erl_crash.dump

test:
	@mkdir -p logs
	@$(REBAR) eunit
	@$(REBAR) ct
	@$(REBAR) proper -c
	@$(REBAR) cover --min_coverage=90

dialyzer:
	@$(REBAR) dialyzer

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

check: clean compile xref dialyzer test
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
