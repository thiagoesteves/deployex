import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

if config_env() == :prod do
  # Set the cloud environment flag
  config :deployex,
    env: System.fetch_env!("DEPLOYEX_CLOUD_ENVIRONMENT"),
    monitored_app_name: System.fetch_env!("DEPLOYEX_MONITORED_APP_NAME"),
    monitored_app_log_path: "/var/log"

  config :ex_aws,
    region: System.fetch_env!("AWS_REGION")
end
