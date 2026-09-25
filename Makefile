# DeployEx developer convenience targets (local).
#
# Thin wrappers over the existing mix / release flow, for discoverability and
# to smooth first-run. These are shell/process/cross-repo commands that do not
# map cleanly to mix aliases (interactive iex with OTP distribution, process
# stop, and a cross-repo sample-app build), so they live here. `make test` is
# just `mix test`.
#
# Run these in a shell whose toolchain matches .tool-versions.

# Local sample monitored app. Override: make dev-app APP_DIR=/path/to/app
APP_DIR  ?= ../myphoenixapp
APP_NAME ?= myphoenixapp
BUCKET   ?= /tmp/deployex/bucket
COOKIE   ?= cookie

.DEFAULT_GOAL := help
.PHONY: help preflight setup start stop test format-check credo dialyzer check dev-app dev-app-clean

preflight: ## Verify the local toolchain (.tool-versions) + tools for dev/test
	@fail=0; \
	exp_erl=$$(awk '/^erlang /{print $$2}' .tool-versions); \
	exp_ex=$$(awk '/^elixir /{print $$2}' .tool-versions); exp_ex_short=$${exp_ex%%-*}; \
	if command -v mise >/dev/null 2>&1; then \
	  run="mise exec --"; printf '  ok    %-10s %s\n' mise "$$(mise --version 2>/dev/null | head -1)"; \
	else \
	  run=""; printf '  warn  %-10s not found; checking ambient toolchain. Install mise (or asdf) to match .tool-versions\n' mise; \
	fi; \
	if $$run elixir --version >/dev/null 2>&1; then \
	  ver=$$($$run elixir --version 2>/dev/null | tr '\n' ' ' | tr -s ' '); \
	  printf '  ok    %-10s %s\n' elixir "$$ver"; \
	  echo "$$ver" | grep -q "Elixir $$exp_ex_short" || \
	    printf '  warn  %-10s expected Elixir %s / Erlang %s per .tool-versions; run: mise install\n' "" "$$exp_ex_short" "$$exp_erl"; \
	else \
	  printf '  MISS  %-10s not runnable. Run: mise install  (expected Erlang %s / Elixir %s)\n' elixir "$$exp_erl" "$$exp_ex"; fail=1; \
	fi; \
	if command -v jq >/dev/null 2>&1; then printf '  ok    %-10s %s\n' jq "$$(jq --version 2>/dev/null)"; \
	else printf '  MISS  %-10s install: brew install jq  (used by make dev-app)\n' jq; fail=1; fi; \
	if [ $$fail -eq 0 ]; then echo "Local prerequisites OK - no need to run 'make setup'."; \
	else echo "Missing prerequisites (see MISS above). Run 'make setup' to install the toolchain + deps."; exit 1; fi

setup: ## Install the pinned toolchain (mise) + fetch deps
	@command -v mise >/dev/null 2>&1 || { echo "mise not found. Install mise (https://mise.jdx.dev) or use asdf with .tool-versions."; exit 1; }
	mise install
	mise exec -- mix deps.get

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

start: ## Run DeployEx locally with OTP distribution (interactive)
	iex --sname deployex --cookie $(COOKIE) -S mix phx.server

stop: ## Stop a locally running DeployEx node (best effort)
	-@pkill -f "sname deployex .*-S mix phx.server" && echo "stopped" || echo "not running"

test: ## Run the full umbrella test suite
	mix test

format-check: ## Check formatting without writing changes
	mix format --check-formatted

credo: ## Run credo static analysis (strict)
	mix credo --strict

dialyzer: ## Run dialyzer static type analysis
	mix dialyzer

check: format-check credo dialyzer test ## Run all pre-PR checks: format, credo, dialyzer, test

dev-app: preflight ## Build + publish the sample app to the local bucket so DeployEx manages it
	@test -d "$(APP_DIR)" || { \
		echo "APP_DIR '$(APP_DIR)' not found. Clone the sample app or pass APP_DIR=/path/to/app."; \
		echo "  git clone https://github.com/thiagoesteves/myphoenixapp $(APP_DIR)"; \
		exit 1; }
	mkdir -p "$(BUCKET)/dist/$(APP_NAME)" "$(BUCKET)/versions/$(APP_NAME)/local"
	cd "$(APP_DIR)" && mix deps.get && MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release
	@TARBALL=$$(ls -t "$(APP_DIR)"/_build/prod/$(APP_NAME)-*.tar.gz | head -1); \
	VERSION=$$(basename "$$TARBALL" | sed -E 's/^$(APP_NAME)-(.*)\.tar\.gz$$/\1/'); \
	cp "$$TARBALL" "$(BUCKET)/dist/$(APP_NAME)/"; \
	echo "{\"version\":\"$$VERSION\",\"pre_commands\":[],\"hash\":\"local\"}" \
		| jq > "$(BUCKET)/versions/$(APP_NAME)/local/current.json"; \
	echo "Published $(APP_NAME) $$VERSION to $(BUCKET). DeployEx picks it up on its next tick."

dev-app-clean: ## Remove the local bucket
	rm -rf "$(BUCKET)"
