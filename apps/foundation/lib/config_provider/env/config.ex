defmodule Foundation.ConfigProvider.Env.Config do
  @moduledoc """
  https://hexdocs.pm/elixir/main/Config.Provider.html

  The DeployEx runtime configuration will be provided by a YAML file
  and can be changed without new deployments
  """
  @behaviour Config.Provider

  alias Foundation.Yaml

  require Logger

  @impl Config.Provider
  def init(_path), do: []

  @doc """
  load/2.

  Args:
    - config is the current config
    - opts is just the return value of init/1.

  Calls out to read, parse and apply the configurations defined in the YAML file.
  """
  @impl Config.Provider
  # credo:disable-for-lines:1
  def load(config, _opts) do
    Logger.info("[Config Provider] Loading configuration from Yaml file")

    case Yaml.load() do
      {:ok, yaml_config} ->
        # Foundation Config
        updated_config = [
          foundation:
            [
              {:env, yaml_config.account_name},
              {:applications, yaml_config.applications},
              {:config_checksum, yaml_config.config_checksum},
              {:monitoring, yaml_config.monitoring}
            ] ++
              add_if_not_nil(yaml_config, :logs_retention_time_ms) ++
              add_if_not_nil(yaml_config, :deploy_rollback_timeout_ms) ++
              add_if_not_nil(yaml_config, :deploy_schedule_interval_ms)
        ]

        # AWS Config
        updated_config =
          if yaml_config.aws_region do
            Keyword.merge(updated_config, ex_aws: [{:region, yaml_config.aws_region}])
          else
            updated_config
          end

        # Endpoint Config
        updated_config =
          Config.Reader.merge(updated_config,
            deployex_web: [
              {DeployexWeb.Endpoint,
               [
                 url: [host: yaml_config.hostname],
                 http: [port: yaml_config.port]
               ]}
            ]
          )

        # Telemetry Config
        updated_config =
          if yaml_config.metrics_retention_time_ms do
            Config.Reader.merge(updated_config,
              observer_web: [{:data_retention_period, yaml_config.metrics_retention_time_ms}]
            )
          else
            updated_config
          end

        # GCP Config (Goth)
        updated_config =
          if yaml_config.google_credentials do
            Config.Reader.merge(updated_config,
              goth: [{:file_credentials, yaml_config.google_credentials}]
            )
          else
            updated_config
          end

        # Release Config
        updated_config =
          Config.Reader.merge(updated_config,
            deployer: [
              {Deployer.Release,
               [
                 {:adapter, yaml_config.release_adapter},
                 {:bucket, yaml_config.release_bucket}
               ]}
            ]
          )

        # Secrets Config
        updated_config =
          Config.Reader.merge(updated_config,
            foundation: [
              {Foundation.ConfigProvider.Secrets.Manager,
               [
                 {:adapter, yaml_config.secrets_adapter},
                 {:path, yaml_config.secrets_path}
               ]}
            ]
          )

        # NOTE: Merge original config with the constructed config from yaml file
        Config.Reader.merge(config, updated_config)

      {:error, :not_found} ->
        Logger.warning("YAML file not found, default configuration will be applied")

      {:error, _reason} ->
        Logger.error("Error loading the YAML file, default configuration will be applied")

        config
    end
  end

  defp add_if_not_nil(config, key) do
    case Map.get(config, key) do
      nil -> []
      value -> [{key, value}]
    end
  end
end
