defmodule Deployex.ConfigProvider.Env.Config do
  @moduledoc """
  https://hexdocs.pm/elixir/main/Config.Provider.html

  The DeployEx runtime configuration will be provided by a YAML file
  and can be changed without new deployments
  """
  @behaviour Config.Provider

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
    yaml_path = System.get_env("DEPLOYEX_CONFIG_YAML_PATH")

    Logger.info("Reading deployex configuration file at: #{yaml_path}")

    {:ok, _} = Application.ensure_all_started(:yaml_elixir)

    case YamlElixir.read_from_file(yaml_path) do
      {:ok, data} ->
        # DeployEx only suports one application for now
        application = Enum.at(data["applications"], 0)

        name = application["name"]
        replicas = application["replicas"]
        monitored_app_lang = application["language"]
        monitored_app_start_port = application["initial_port"]
        env = data["account_name"]

        monitored_app_env =
          Enum.map(application["env"], fn %{"key" => key, "value" => value} ->
            "#{key}=#{value}"
          end)

        updated_config = [
          deployex: [
            {:env, env},
            {:monitored_app_name, name},
            {:replicas, replicas},
            {:monitored_app_lang, monitored_app_lang},
            {:monitored_app_start_port, monitored_app_start_port},
            {:monitored_app_env, monitored_app_env}
          ]
        ]

        # AWS Config
        aws_region = data["aws_region"]

        updated_config =
          if aws_region do
            Keyword.merge(updated_config, ex_aws: [{:region, aws_region}])
          else
            updated_config
          end

        # Endpoint Config
        hostname = data["hostname"]
        port = data["port"]

        updated_config =
          merge_deployex_config(updated_config, [
            {DeployexWeb.Endpoint,
             [
               url: [host: hostname],
               http: [port: port]
             ]}
          ])

        # Telemetry Config
        metrics_retention_time_ms = data["metrics_retention_time_ms"]

        updated_config =
          if metrics_retention_time_ms do
            Keyword.merge(updated_config,
              observer_web: [
                {ObserverWeb.Telemetry, [{:data_retention_period, metrics_retention_time_ms}]}
              ]
            )
          else
            updated_config
          end

        logs_retention_time_ms = data["logs_retention_time_ms"]

        updated_config =
          if logs_retention_time_ms do
            merge_deployex_config(updated_config, [
              {Deployex.Logs,
               [
                 {:data_retention_period, logs_retention_time_ms}
               ]}
            ])
          else
            updated_config
          end

        # Deployment Config
        deploy_timeout_rollback_ms = data["deploy_timeout_rollback_ms"]
        deploy_schedule_interval_ms = data["deploy_schedule_interval_ms"]

        updated_config =
          merge_deployex_config(updated_config, [
            {Deployex.Deployment,
             [
               {:timeout_rollback, deploy_timeout_rollback_ms},
               {:schedule_interval, deploy_schedule_interval_ms}
             ]}
          ])

        # GCP Config (Goth)
        google_credentials = data["google_credentials"]

        updated_config =
          if google_credentials do
            Keyword.merge(updated_config, goth: [{:file_credentials, google_credentials}])
          else
            updated_config
          end

        # Release Config
        yaml_release_adapter = data["release_adapter"]
        release_bucket = data["release_bucket"]

        release_adapter =
          case yaml_release_adapter do
            "gcp-storage" ->
              Deployex.Release.GcpStorage

            "s3" ->
              Deployex.Release.S3

            adapter ->
              raise "Release #{adapter} not supported"
          end

        updated_config =
          merge_deployex_config(updated_config, [
            {Deployex.Release,
             [
               {:adapter, release_adapter},
               {:bucket, release_bucket}
             ]}
          ])

        # Secrets Config
        yaml_secrets_adapter = data["secrets_adapter"]
        secrets_path = data["secrets_path"]

        secrets_adapter =
          case yaml_secrets_adapter do
            "gcp" ->
              Deployex.ConfigProvider.Secrets.Gcp

            "aws" ->
              Deployex.ConfigProvider.Secrets.Aws

            adapter ->
              raise "Secret #{adapter} not supported"
          end

        updated_config =
          merge_deployex_config(updated_config, [
            {Deployex.ConfigProvider.Secrets.Manager,
             [
               {:adapter, secrets_adapter},
               {:path, secrets_path}
             ]}
          ])

        Config.Reader.merge(config, updated_config)

      {:error, _} ->
        Logger.warning(
          "No file found or decoded at #{yaml_path}, default configuration will be applied"
        )

        config
    end
  end

  defp merge_deployex_config(current_config, keywords) do
    updated_deployex =
      current_config
      |> Keyword.get(:deployex)
      |> Keyword.merge(keywords)

    Keyword.merge(current_config, deployex: updated_deployex)
  end
end
