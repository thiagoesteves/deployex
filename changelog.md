# Changelog for Elixir v0.2.0

This release marks a transformation of the application, transitioning it into a Phoenix LiveView app featuring a dashboard providing real-time status updates on the current deployment.

# Production Configuration and Required Secrets:

 ```bash
DEPLOYEX_SECRET_KEY_BASE=xxxxxxx <--- This secret is expected from AWS secrets
DEPLOYEX_ERLANG_COOKIE=xxxxxx <--- This secret is expected from AWS secrets
DEPLOYEX_MONITORED_APP_NAME=myphoenixapp
DEPLOYEX_STORAGE_ADAPTER=s3
DEPLOYEX_CLOUD_ENVIRONMENT=prod
DEPLOYEX_PHX_SERVER=true
DEPLOYEX_PHX_HOST=example.com
DEPLOYEX_PHX_PORT=5001
AWS_REGION=us-east2
```

## Supported Hosts
 * Ubuntu 20.04
 * Ubuntu 22.04
