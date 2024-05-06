.PHONY: help tls-distribution-certs

default: help

#❓ help: @ Displays this message
help:
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(firstword $(MAKEFILE_LIST))| tr -d '#'  | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'

#🔒 tls-distribution-certs: @ Create CA certificates (Requires privileges)
tls-distribution-certs:
	@./devops/scripts/tls-distribution-certs
