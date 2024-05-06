# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

monitored_app_name = System.get_env("DEPLOYEX_MONITORED_APP_NAME", "myphoenixapp")

config :deployex,
  env: "local",
  monitored_app_name: monitored_app_name,
  monitored_app_log_path: "/tmp/#{monitored_app_name}",
  base_path: "/tmp/deployex/varlib"

# Configures Elixir's Logger
config :logger, :console,
  format: "$time [$level] $metadata $message\n",
  metadata: [:module, :function, :pid]

# AWS Configuration
config :ex_aws,
  access_key_id: [
    {:system, "AWS_ACCESS_KEY_ID"},
    {:awscli, :system, 30},
    :instance_role
  ],
  secret_access_key: [
    {:system, "AWS_SECRET_ACCESS_KEY"},
    {:awscli, :system, 30},
    :instance_role
  ]

config :deployex, Deployex.Storage, adapter: Deployex.Storage.Local

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
