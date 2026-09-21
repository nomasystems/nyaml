.PHONY: all compile test check dialyzer fmt docs clean distclean shell help compliance

REBAR3 ?= rebar3

all: compile

compile: ## Build the project
	$(REBAR3) compile

test: ## Run EUnit and Common Test suites with coverage report
	$(REBAR3) test

check: ## Run fmt --check and dialyzer
	$(REBAR3) check

dialyzer: ## Run Dialyzer static analysis
	$(REBAR3) dialyzer

fmt: ## Format code with erlfmt
	$(REBAR3) fmt

docs: ## Generate documentation with ex_doc
	$(REBAR3) ex_doc

compliance: ## Run YAML test suite compliance tests
	$(REBAR3) compliance

clean: ## Clean build artifacts
	$(REBAR3) clean

distclean: clean ## Clean everything including deps and _build
	rm -rf _build

shell: ## Start an Erlang shell with the project loaded
	$(REBAR3) shell

help: ## Show this help
	@echo "nyaml - YAML parser for Erlang"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
