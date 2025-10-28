defmodule Foundation.Yaml do
  @moduledoc """
  Parses and validates Deployex YAML configuration files.

  Provides structured access to deployment configuration including applications,
  monitoring settings, release adapters, and environment variables.

  The configuration is loaded from a YAML file specified by the 
  `DEPLOYEX_CONFIG_YAML_PATH` environment variable.
  """

  require Logger

  defmodule Monitoring do
    @moduledoc false

    defstruct [
      :type,
      :enable_restart,
      :warning_threshold_percent,
      :restart_threshold_percent
    ]

    @type t :: %__MODULE__{
            type: String.t(),
            enable_restart: boolean(),
            warning_threshold_percent: non_neg_integer(),
            restart_threshold_percent: non_neg_integer()
          }
  end

  defmodule Ports do
    @moduledoc false

    defstruct [:key, :base]

    @type t :: %__MODULE__{
            key: String.t(),
            base: non_neg_integer()
          }
  end

  defmodule KV do
    @moduledoc false

    defstruct [:key, :value]

    @type t :: %__MODULE__{
            key: String.t(),
            value: non_neg_integer()
          }
  end

  defmodule Application do
    @moduledoc false

    defstruct [
      :name,
      :language,
      :replicas,
      :replica_ports,
      :env,
      :monitoring
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            language: String.t(),
            replicas: non_neg_integer(),
            replica_ports: [Foundation.Yaml.Ports.t()],
            env: [Foundation.Yaml.KV.t()],
            monitoring: [Foundation.Yaml.Monitoring.t()]
          }
  end

  defstruct [
    :account_name,
    :hostname,
    :port,
    :release_adapter,
    :release_bucket,
    :secrets_adapter,
    :secrets_path,
    :google_credentials,
    :aws_region,
    :version,
    :otp_version,
    :otp_tls_certificates,
    :os_target,
    :deploy_rollback_timeout_ms,
    :deploy_schedule_interval_ms,
    :metrics_retention_time_ms,
    :logs_retention_time_ms,
    :monitoring,
    :applications
  ]

  @type t :: %__MODULE__{
          account_name: String.t(),
          hostname: String.t(),
          port: non_neg_integer(),
          release_adapter: String.t(),
          release_bucket: String.t(),
          secrets_adapter: String.t(),
          secrets_path: String.t() | nil,
          google_credentials: String.t() | nil,
          aws_region: String.t() | nil,
          version: String.t(),
          otp_version: non_neg_integer(),
          otp_tls_certificates: String.t() | nil,
          os_target: String.t(),
          deploy_rollback_timeout_ms: non_neg_integer(),
          deploy_schedule_interval_ms: non_neg_integer(),
          metrics_retention_time_ms: non_neg_integer(),
          logs_retention_time_ms: non_neg_integer(),
          monitoring: [Foundation.Yaml.Monitoring.t()],
          applications: [Foundation.Yaml.Application.t()]
        }

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Loads and parses the Deployex YAML configuration file.

  Reads the YAML configuration file from the path specified in the 
  `DEPLOYEX_CONFIG_YAML_PATH` environment variable and parses it into 
  a structured `Foundation.Yaml` struct with all nested configurations.

  The configuration file path is read from an environment variable rather 
  than application config to ensure it can be loaded during the config 
  provider phase, before the application configuration is fully available.

  ## Returns

    * `{:ok, %Foundation.Yaml{}}` - Successfully loaded and parsed configuration
    * `{:error, reason}` - Failed to read or parse the YAML file

  ## Examples

      iex> System.put_env("DEPLOYEX_CONFIG_YAML_PATH", "/path/to/config.yaml")
      iex> Foundation.Yaml.load()
      {:ok, %Foundation.Yaml{
        account_name: "prod",
        hostname: "deployex.example.com",
        port: 5001,
        applications: [%Foundation.Yaml.Application{name: "myapp", ...}],
        ...
      }}

  ## Environment Variables

    * `DEPLOYEX_CONFIG_YAML_PATH` - Required. Full path to the Deployex YAML configuration file.

  """
  @spec load() :: {:ok, t()} | {:error, any()}
  def load do
    # NOTE: The configuration path is read from an environment variable instead of
    # application config because this function must be callable during the config
    # provider initialization phase, before Application.get_env/2 is available.
    yaml_path = System.get_env("DEPLOYEX_CONFIG_YAML_PATH")

    Logger.info("Reading deployex configuration file at: #{yaml_path}")

    {:ok, _} = Elixir.Application.ensure_all_started(:yaml_elixir)

    case YamlElixir.read_from_file(yaml_path) do
      {:ok, data} ->
        config = parse(data)
        {:ok, config}

      {:error, reason} ->
        Logger.error(
          "Error while trying to read and decoded at #{yaml_path} reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  @spec parse(map()) :: t()
  defp parse(data) do
    %__MODULE__{
      account_name: data["account_name"],
      hostname: data["hostname"],
      port: data["port"],
      release_adapter: data["release_adapter"],
      release_bucket: data["release_bucket"],
      secrets_adapter: data["secrets_adapter"],
      secrets_path: data["secrets_path"],
      google_credentials: data["google_credentials"],
      version: data["version"],
      otp_version: data["otp_version"],
      otp_tls_certificates: data["otp_tls_certificates"],
      os_target: data["os_target"],
      deploy_rollback_timeout_ms: data["deploy_rollback_timeout_ms"],
      deploy_schedule_interval_ms: data["deploy_schedule_interval_ms"],
      metrics_retention_time_ms: data["metrics_retention_time_ms"],
      logs_retention_time_ms: data["logs_retention_time_ms"],
      monitoring: parse_monitoring_list(data["monitoring"]),
      applications: parse_applications(data["applications"])
    }
  end

  @spec parse_monitoring_list(list(map()) | nil) :: [Foundation.Yaml.Monitoring.t()]
  defp parse_monitoring_list(nil), do: []

  defp parse_monitoring_list(monitoring_list) do
    Enum.map(monitoring_list, &parse_monitoring/1)
  end

  @spec parse_monitoring(map()) :: Foundation.Yaml.Monitoring.t()
  defp parse_monitoring(data) do
    %Foundation.Yaml.Monitoring{
      type: data["type"],
      enable_restart: data["enable_restart"],
      warning_threshold_percent: data["warning_threshold_percent"],
      restart_threshold_percent: data["restart_threshold_percent"]
    }
  end

  @spec parse_applications(list(map()) | nil) :: [Foundation.Yaml.Application.t()]
  defp parse_applications(nil), do: []

  defp parse_applications(apps) do
    Enum.map(apps, &parse_application/1)
  end

  @spec parse_application(map()) :: Foundation.Yaml.Application.t()
  defp parse_application(data) do
    %Foundation.Yaml.Application{
      name: data["name"],
      language: data["language"],
      replicas: data["replicas"],
      replica_ports: parse_ports(data["replica_ports"]),
      env: parse_env(data["env"]),
      monitoring: parse_monitoring_list(data["monitoring"])
    }
  end

  @spec parse_ports(list(map()) | nil) :: [Foundation.Yaml.Ports.t()]
  defp parse_ports(nil), do: []

  defp parse_ports(ports) do
    Enum.map(ports, fn port ->
      %Ports{
        key: port["key"],
        base: port["base"]
      }
    end)
  end

  @spec parse_env(list(map()) | nil) :: [KV.t()]
  defp parse_env(nil), do: []

  defp parse_env(env_list) do
    Enum.map(env_list, fn env ->
      %KV{
        key: env["key"],
        value: normalize_value(env["value"])
      }
    end)
  end

  # Helper to convert values to strings for consistency
  @spec normalize_value(any()) :: String.t()
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_boolean(value), do: to_string(value)
  defp normalize_value(value), do: to_string(value)
end
