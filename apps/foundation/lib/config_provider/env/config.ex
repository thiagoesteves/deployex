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
          foundation: [
            {:env, yaml_config.account_name},
            {:applications, yaml_config.applications},
            {:config_checksum, yaml_config.config_checksum},
            {:monitoring, yaml_config.monitoring},
            {:notifications, yaml_config.notifications},
            {:logs_retention_time_ms, yaml_config.logs_retention_time_ms},
            {:install_path, yaml_config.install_path},
            {:var_path, yaml_config.var_path},
            {:log_path, yaml_config.log_path},
            {:monitored_app_log_path, yaml_config.monitored_app_log_path}
          ]
        ]

        # AWS Config
        updated_config =
          if yaml_config.aws_region do
            Keyword.merge(updated_config, ex_aws: [{:region, yaml_config.aws_region}])
          else
            updated_config
          end

        # Self-Upgrade Config
        self_upgrade = yaml_config.self_upgrade

        updated_config =
          if self_upgrade.enabled do
            Config.Reader.merge(updated_config,
              deployer: [
                {Deployer.SelfUpgrade,
                 [
                   enabled: true,
                   interval_ms: self_upgrade.interval_ms,
                   dist_base_url: self_upgrade.dist_base_url,
                   script: self_upgrade.installer_script
                 ]},
                {Deployer.SelfUpgrade.Source,
                 [adapter: self_upgrade_source_adapter(self_upgrade.source)]}
              ]
            )
          else
            updated_config
          end

        # Endpoint Config. url is the public address, http is the listen port.
        endpoint_opts =
          [url: endpoint_url(yaml_config), http: [port: yaml_config.port]]
          |> maybe_put(:check_origin, yaml_config.check_origin)

        updated_config =
          Config.Reader.merge(updated_config,
            deployex_web: [{DeployexWeb.Endpoint, endpoint_opts}]
          )

        # Telemetry Config
        updated_config =
          Config.Reader.merge(updated_config,
            observer_web: [{:data_retention_period, yaml_config.metrics_retention_time_ms}]
          )

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
        Logger.warning(
          "DEPLOYEX_CONFIG_YAML_PATH not defined, default configuration will be applied"
        )

        config

      {:error, _reason} ->
        Logger.error("Error loading the YAML file, default configuration will be applied")

        config
    end
  end

  # Phoenix does not derive the url port from the scheme, so set both. Without a
  # scheme the release config (https on 443) stays.
  defp endpoint_url(%Yaml{scheme: "https"} = yaml_config),
    do: [host: yaml_config.hostname, scheme: "https", port: 443]

  defp endpoint_url(%Yaml{scheme: "http"} = yaml_config),
    do: [host: yaml_config.hostname, scheme: "http", port: 80]

  defp endpoint_url(yaml_config), do: [host: yaml_config.hostname]

  # Adds key only when the value is not nil, so an absent yaml value keeps the
  # existing (Phoenix default) config instead of overriding it with nil.
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  # NOTE: these are only used as config keys/values (atoms), never aliased or called
  #       directly, to avoid a foundation -> deployer compile-time dependency.
  defp self_upgrade_source_adapter("aws"), do: Deployer.SelfUpgrade.Source.Aws
  defp self_upgrade_source_adapter("gcp"), do: Deployer.SelfUpgrade.Source.Gcp
  defp self_upgrade_source_adapter(_source), do: Deployer.SelfUpgrade.Source.Local
end
