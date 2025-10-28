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
            name: atom(),
            language: String.t(),
            replicas: non_neg_integer(),
            replica_ports: [Foundation.Yaml.Ports.t()],
            env: [String.t()],
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
    :applications,
    :config_checksum
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
          applications: [Foundation.Yaml.Application.t()],
          # Checksum of the YAML configuration file content.
          # Used internally to detect configuration changes and trigger dynamic reloads.
          # This value is computed from the file contents, not the file metadata.
          config_checksum: String.t() | nil
        }

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Loads and parses the Deployex YAML configuration file.

  Reads the YAML configuration file from the path specified in the 
  `DEPLOYEX_CONFIG_YAML_PATH` environment variable and parses it into 
  a structured `Foundation.Yaml` struct with all nested configurations.

  When an existing configuration is provided, the function first checks if 
  the file has changed by comparing checksums. If unchanged, returns the 
  existing configuration without reparsing.

  The configuration file path is read from an environment variable rather 
  than application config to ensure it can be loaded during the config 
  provider phase, before the application configuration is fully available.

  ## Parameters

    * `existing_config` - Optional. Previously loaded configuration to check against.

  ## Returns

    * `{:ok, %Foundation.Yaml{}}` - Successfully loaded and parsed configuration
    * `{:ok, :unchanged}` - Configuration file hasn't changed (when existing_config provided)
    * `{:error, reason}` - Failed to read or parse the YAML file

  ## Examples

      # Initial load
      iex> System.put_env("DEPLOYEX_CONFIG_YAML_PATH", "/path/to/config.yaml")
      iex> Foundation.Yaml.load()
      {:ok, %Foundation.Yaml{account_name: "prod", config_checksum: "abc123...", ...}}

      # Reload with checksum check
      iex> {:ok, config} = Foundation.Yaml.load()
      iex> Foundation.Yaml.load(config)
      {:ok, :unchanged}

      # After file changes
      iex> Foundation.Yaml.load(config)
      {:ok, %Foundation.Yaml{account_name: "prod", config_checksum: "def456...", ...}}

  ## Environment Variables

    * `DEPLOYEX_CONFIG_YAML_PATH` - Required. Full path to the Deployex YAML configuration file.

  """
  @spec load(t() | nil) :: {:ok, t()} | {:ok, :unchanged} | {:error, any()}
  def load(existing_config \\ nil) do
    # NOTE: The configuration path is read from an environment variable instead of
    # application config because this function must be callable during the config
    # provider initialization phase, before Application.get_env/2 is available.
    yaml_path = System.get_env("DEPLOYEX_CONFIG_YAML_PATH")

    Logger.info("Reading deployex configuration file at: #{yaml_path}")

    {:ok, _} = Elixir.Application.ensure_all_started(:yaml_elixir)

    with {:ok, content} <- File.read(yaml_path),
         needs_reload? <- new_config?(existing_config, content),
         {:ok, config} <- maybe_parse(needs_reload?, content) do
      {:ok, config}
    else
      {:error, reason} ->
        Logger.error(
          "Error while trying to read and decode at #{yaml_path} reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  @spec new_config?(t() | nil, binary()) :: boolean()
  defp new_config?(nil, _content), do: true

  defp new_config?(%__MODULE__{config_checksum: old_checksum}, content) do
    new_checksum = compute_checksum(content)

    if old_checksum == new_checksum, do: false, else: true
  end

  @spec maybe_parse(boolean(), binary()) :: {:ok, t() | :unchanged} | {:error, any()}
  defp maybe_parse(false, _content), do: {:ok, :unchanged}

  defp maybe_parse(true, content) do
    checksum = compute_checksum(content)

    case YamlElixir.read_from_string(content) do
      {:ok, data} ->
        config = parse(data, checksum)
        {:ok, config}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec compute_checksum(binary()) :: String.t()
  defp compute_checksum(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  @spec parse(map(), String.t()) :: t()
  defp parse(data, checksum) do
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
      applications: parse_applications(data["applications"]),
      config_checksum: checksum
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
      name: data["name"] |> String.to_atom(),
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

  @spec parse_env(list(map()) | nil) :: [String.t()]
  defp parse_env(nil), do: []

  defp parse_env(env_list) do
    Enum.map(env_list, fn %{"key" => key, "value" => value} ->
      "#{key}=#{value}"
    end)
  end
end
