import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

if config_env() == :prod do
  monitored_app_name = System.fetch_env!("DEPLOYEX_MONITORED_APP_NAME")

  # Set the cloud environment flag
  config :deployex,
    env: System.fetch_env!("DEPLOYEX_CLOUD_ENVIRONMENT"),
    monitored_app_name: monitored_app_name,
    monitored_app_log_path: "/var/log/#{monitored_app_name}"

  # Set the Storage Format
  storage_adapter =
    if(System.fetch_env!("DEPLOYEX_STORAGE_ADAPTER") == "local") do
      Deployex.Storage.Local
    else
      Deployex.Storage.S3
    end

  config :deployex, Deployex.Storage, adapter: storage_adapter
end
