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
.PHONY: help preflight start stop test dev-app dev-app-clean

preflight: ## Check required tools are installed
	@command -v mix >/dev/null 2>&1 || { echo "mix not found. Install Elixir per .tool-versions (see mise / asdf)."; exit 1; }
	@command -v jq  >/dev/null 2>&1 || { echo "jq not found. Install it (e.g. brew install jq)."; exit 1; }

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

start: ## Run DeployEx locally with OTP distribution (interactive)
	iex --sname deployex --cookie $(COOKIE) -S mix phx.server

stop: ## Stop a locally running DeployEx node (best effort)
	-@pkill -f "sname deployex .*-S mix phx.server" && echo "stopped" || echo "not running"

test: ## Run the full umbrella test suite
	mix test

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
