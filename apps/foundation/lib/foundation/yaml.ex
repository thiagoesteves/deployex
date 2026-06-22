defmodule Foundation.Yaml do
  @moduledoc """
  Parses and validates Deployex YAML configuration files.

  Provides structured access to deployment configuration including applications,
  monitoring settings, release adapters, and environment variables.

  The configuration is loaded from a YAML file specified by the 
  `DEPLOYEX_CONFIG_YAML_PATH` environment variable.
  """

  @default_metrics_retention_time_ms :timer.hours(1)
  @default_logs_retention_time_ms :timer.hours(1)
  @default_replicas 3
  @default_language "elixir"
  @default_deploy_rollback_timeout_ms :timer.minutes(10)
  @default_deploy_schedule_interval_ms :timer.seconds(5)
  @default_install_path "/opt/deployex"
  @default_var_path "/var/lib/deployex"
  @default_log_path "/var/log/deployex"
  @default_monitored_app_log_path "/var/log/monitored-apps"
  @default_certificate_renew_before_days 30
  @default_certificate_check_interval_ms 86_400_000
  @default_certificate_dns_propagation_timeout_ms 120_000
  @default_certificate_dns_check_interval_ms 5_000
  @default_certificate_acme_client_url "https://acme-v02.api.letsencrypt.org/directory"
  @default_certificate_acme_key_size 2048
  @default_certificate_acme_propagation_timeout_ms 120_000
  @default_certificate_acme_check_interval_ms 2_000
  @default_certificate_dns_ttl 1

  defmodule Monitoring do
    @moduledoc """
    Provides structure to define monitoring feature
    """

    defstruct [
      :enable_restart,
      :warning_threshold_percent,
      :restart_threshold_percent
    ]

    @type t :: %__MODULE__{
            enable_restart: boolean(),
            warning_threshold_percent: non_neg_integer(),
            restart_threshold_percent: non_neg_integer()
          }
  end

  defmodule Ports do
    @moduledoc """
    Provides structure to define Ports feature
    """

    defstruct [:key, :base]

    @type t :: %__MODULE__{
            key: String.t(),
            base: non_neg_integer()
          }
  end

  defmodule Certificate do
    @moduledoc """
    Provides structure to define Certificate feature
    """

    defmodule DnsOptions do
      @moduledoc "DNS provider options for certificate configuration."
      defstruct [:ttl, :zone, :api_token]

      @type t :: %__MODULE__{
              ttl: non_neg_integer() | nil,
              zone: String.t() | nil,
              api_token: String.t() | nil
            }
    end

    defmodule AcmeOptions do
      @moduledoc "ACME client options for certificate provisioning."
      defstruct [:contact_email, :url, :key_size, :propagation_timeout_ms, :check_interval_ms]

      @type t :: %__MODULE__{
              contact_email: String.t() | nil,
              url: String.t() | nil,
              key_size: non_neg_integer() | nil,
              propagation_timeout_ms: non_neg_integer() | nil,
              check_interval_ms: non_neg_integer() | nil
            }
    end

    defmodule ImporterOptions do
      @moduledoc "Options for importing externally managed certificates."
      defstruct [:certificate_arn]

      @type t :: %__MODULE__{
              certificate_arn: String.t() | nil
            }
    end

    defstruct [
      :type,
      :domains,
      :certificate_check_interval_ms,
      :dns_propagation_timeout_ms,
      :dns_check_interval_ms,
      :renew_before_days,
      :dns_provider,
      :dns_options,
      :acme_provider,
      :acme_options,
      :importer,
      :importer_options
    ]

    @type t :: %__MODULE__{
            type: atom(),
            domains: [String.t()],
            certificate_check_interval_ms: non_neg_integer() | nil,
            dns_propagation_timeout_ms: non_neg_integer() | nil,
            dns_check_interval_ms: non_neg_integer() | nil,
            renew_before_days: non_neg_integer() | nil,
            dns_provider: atom() | nil,
            dns_options: __MODULE__.DnsOptions.t() | nil,
            acme_provider: atom() | nil,
            acme_options: __MODULE__.AcmeOptions.t() | nil,
            importer: atom() | nil,
            importer_options: __MODULE__.ImporterOptions.t() | nil
          }
  end

  defmodule Notification do
    @moduledoc """
    Configuration for a single notification channel.

    Each entry in the top-level `notifications:` YAML list is parsed into one of
    these structs and stored in the `:foundation` application environment under
    the `:notifications` key.

    ## Fields

    - `:adapter`  — the module that handles delivery (e.g. `Foundation.Notifications.Webhook`)
    - `:url`      — destination URL; required for `webhook` and `slack`, optional for `pagerduty`
                    (which defaults to the standard Events API endpoint)
    - `:enabled`  — set to `false` to silence a channel without removing it; defaults to `true`
    - `:events`   — list of event atoms this channel subscribes to (empty list = no deliveries)
    - `:options`  — adapter-specific key/value pairs parsed directly from the YAML `options:` map

    ## Adapter-specific options

    | Adapter     | Key             | Required | Description                              |
    |-------------|-----------------|----------|------------------------------------------|
    | `pagerduty` | `routing_key`   | yes      | PagerDuty integration / routing key      |
    | `slack`     | `username`      | no       | Bot display name (default: `"DeployEx"`) |
    | `slack`     | `icon_emoji`    | no       | Bot emoji icon (default: `":robot_face:"`) |
    """

    defmodule Options do
      @moduledoc "Options for notification configuration."
      defstruct [:routing_key, :username, :icon_emoji]

      @type t :: %__MODULE__{
              routing_key: String.t() | nil,
              username: String.t() | nil,
              icon_emoji: String.t() | nil
            }
    end

    defstruct [:adapter, :url, :enabled, :events, options: %{}]

    @type t :: %__MODULE__{
            adapter: module(),
            url: String.t() | nil,
            enabled: boolean(),
            events: [atom()],
            options: __MODULE__.Options.t() | nil
          }
  end

  defmodule Application do
    @moduledoc """
    Provides structure to define Application feature
    """

    defstruct [
      :name,
      :language,
      :replicas,
      :deploy_rollback_timeout_ms,
      :deploy_schedule_interval_ms,
      :replica_ports,
      :env,
      :monitoring,
      :certificates
    ]

    @type t :: %__MODULE__{
            name: atom(),
            language: String.t(),
            replicas: non_neg_integer(),
            deploy_rollback_timeout_ms: non_neg_integer() | nil,
            deploy_schedule_interval_ms: non_neg_integer() | nil,
            replica_ports: [Foundation.Yaml.Ports.t()],
            env: [String.t()],
            monitoring: [{atom(), Foundation.Yaml.Monitoring.t()}],
            certificates: [Foundation.Yaml.Certificate.t()]
          }
  end

  defstruct account_name: nil,
            hostname: nil,
            port: nil,
            release_adapter: nil,
            release_bucket: nil,
            secrets_adapter: nil,
            secrets_path: nil,
            google_credentials: nil,
            aws_region: nil,
            version: nil,
            otp_version: nil,
            otp_tls_certificates: nil,
            os_target: nil,
            install_path: nil,
            log_path: nil,
            monitored_app_log_path: nil,
            var_path: nil,
            metrics_retention_time_ms: nil,
            logs_retention_time_ms: nil,
            monitoring: [],
            applications: [],
            notifications: [],
            config_checksum: nil

  @type t :: %__MODULE__{
          account_name: String.t() | nil,
          hostname: String.t() | nil,
          port: non_neg_integer() | nil,
          release_adapter: atom() | nil,
          release_bucket: String.t() | nil,
          secrets_adapter: atom() | nil,
          secrets_path: String.t() | nil,
          google_credentials: String.t() | nil,
          aws_region: String.t() | nil,
          version: String.t() | nil,
          otp_version: non_neg_integer() | nil,
          otp_tls_certificates: String.t() | nil,
          os_target: String.t() | nil,
          install_path: String.t() | nil,
          var_path: String.t() | nil,
          log_path: String.t() | nil,
          monitored_app_log_path: String.t() | nil,
          metrics_retention_time_ms: non_neg_integer() | nil,
          logs_retention_time_ms: non_neg_integer() | nil,
          monitoring: [{atom(), Foundation.Yaml.Monitoring.t()}] | [],
          applications: [Foundation.Yaml.Application.t()] | [],
          notifications: [Foundation.Yaml.Notification.t()] | [],
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
    * `{:error, :unchanged}` - Configuration file hasn't changed (when existing_config provided)
    * `{:error, reason}` - Failed to read or parse the YAML file

  ## Examples

      # Initial load
      iex> Foundation.Yaml.load()
      {:ok, %Foundation.Yaml{account_name: "prod", config_checksum: "abc123...", ...}}

      # Reload with checksum check
      iex> {:ok, config} = Foundation.Yaml.load()
      iex> Foundation.Yaml.load(config)
      {:error, :unchanged}

      # After file changes
      iex> Foundation.Yaml.load(config)
      {:ok, %Foundation.Yaml{account_name: "prod", config_checksum: "def456...", ...}}

  ## Environment Variables

    * `DEPLOYEX_CONFIG_YAML_PATH` - Required. Full path to the Deployex YAML configuration file.

  """
  @spec load(existing_config :: t() | nil) :: {:ok, t()} | {:error, any()}
  def load(existing_config \\ nil) do
    # NOTE: The configuration path is read from an environment variable instead of
    # application config because this function must be callable during the config
    # provider initialization phase, before Application.get_env/2 is available.
    yaml_path = System.get_env("DEPLOYEX_CONFIG_YAML_PATH")

    if yaml_path do
      # NOTE: Required because it runs on configuration provider
      {:ok, _} = Elixir.Application.ensure_all_started(:yaml_elixir)

      with {:ok, content} <- File.read(yaml_path),
           needs_reload? <- new_config?(existing_config, content) do
        maybe_parse(needs_reload?, content)
      end
    else
      {:error, :not_found}
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp new_config?(nil, _content), do: true

  defp new_config?(%__MODULE__{config_checksum: old_checksum}, content) do
    new_checksum = compute_checksum(content)

    if old_checksum == new_checksum, do: false, else: true
  end

  defp maybe_parse(false, _content), do: {:error, :unchanged}

  defp maybe_parse(true, content) do
    checksum = compute_checksum(content)

    with {:ok, data} <- YamlElixir.read_from_string(content) do
      {:ok, parse(data, checksum)}
    end
  end

  defp compute_checksum(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp parse(data, checksum) do
    %__MODULE__{
      account_name: data["account_name"],
      hostname: data["hostname"],
      port: data["port"],
      release_adapter: release_adapter(data["release_adapter"]),
      release_bucket: data["release_bucket"],
      secrets_adapter: secrets_adapter(data["secrets_adapter"]),
      secrets_path: data["secrets_path"],
      google_credentials: data["google_credentials"],
      aws_region: data["aws_region"],
      version: data["version"],
      otp_version: data["otp_version"],
      otp_tls_certificates: data["otp_tls_certificates"],
      os_target: data["os_target"],
      install_path: data["install_path"] || @default_install_path,
      var_path: data["var_path"] || @default_var_path,
      log_path: data["log_path"] || @default_log_path,
      monitored_app_log_path: data["monitored_app_log_path"] || @default_monitored_app_log_path,
      metrics_retention_time_ms:
        data["metrics_retention_time_ms"] || @default_metrics_retention_time_ms,
      logs_retention_time_ms: data["logs_retention_time_ms"] || @default_logs_retention_time_ms,
      monitoring: parse_monitoring_list(data["monitoring"]),
      applications: parse_applications(data["applications"]),
      notifications: parse_notifications(data["notifications"]),
      config_checksum: checksum
    }
  end

  defp secrets_adapter("aws"), do: Foundation.ConfigProvider.Secrets.Aws
  defp secrets_adapter("gcp"), do: Foundation.ConfigProvider.Secrets.Gcp
  defp secrets_adapter("env"), do: Foundation.ConfigProvider.Secrets.Env
  defp secrets_adapter(adapter), do: raise("Secret #{adapter} not supported")

  defp release_adapter("s3"), do: Deployer.Release.S3
  defp release_adapter("gcp-storage"), do: Deployer.Release.GcpStorage
  defp release_adapter("local"), do: Deployer.Release.Local
  defp release_adapter(adapter), do: raise("Release #{adapter} not supported")

  defp parse_monitoring_list(nil), do: []

  defp parse_monitoring_list(monitoring_list) do
    Enum.map(monitoring_list, &parse_monitoring/1)
  end

  defp parse_monitoring(data) do
    {data["type"] |> String.to_atom(),
     %Foundation.Yaml.Monitoring{
       enable_restart: data["enable_restart"],
       warning_threshold_percent: data["warning_threshold_percent"],
       restart_threshold_percent: data["restart_threshold_percent"]
     }}
  end

  defp parse_applications(nil), do: []

  defp parse_applications(apps) do
    Enum.map(apps, &parse_application/1)
  end

  defp parse_application(data) do
    %Foundation.Yaml.Application{
      name: data["name"],
      language: data["language"] || @default_language,
      replicas: data["replicas"] || @default_replicas,
      deploy_rollback_timeout_ms:
        data["deploy_rollback_timeout_ms"] || @default_deploy_rollback_timeout_ms,
      deploy_schedule_interval_ms:
        data["deploy_schedule_interval_ms"] || @default_deploy_schedule_interval_ms,
      replica_ports: parse_ports(data["replica_ports"]),
      env: parse_env(data["env"]),
      monitoring: parse_monitoring_list(data["monitoring"]),
      certificates: parse_certificates(data["certificates"])
    }
  end

  defp parse_ports(nil), do: []

  defp parse_ports(ports) do
    Enum.map(ports, fn port ->
      %Ports{
        key: port["key"],
        base: port["base"]
      }
    end)
  end

  defp parse_env(nil), do: []

  defp parse_env(env_list) do
    Enum.map(env_list, fn %{"key" => key, "value" => value} ->
      "#{key}=#{value}"
    end)
  end

  defp parse_certificates(nil), do: []

  defp parse_certificates(certs) do
    Enum.map(certs, &parse_certificate/1)
  end

  defp parse_certificate(data) do
    %Foundation.Yaml.Certificate{
      type: data["type"] |> String.to_atom(),
      domains: data["domains"] || [],
      certificate_check_interval_ms:
        data["certificate_check_interval_ms"] || @default_certificate_check_interval_ms,
      dns_propagation_timeout_ms:
        data["dns_propagation_timeout_ms"] || @default_certificate_dns_propagation_timeout_ms,
      dns_check_interval_ms:
        data["dns_check_interval_ms"] || @default_certificate_dns_check_interval_ms,
      renew_before_days: data["renew_before_days"] || @default_certificate_renew_before_days,
      dns_provider: parse_dns_provider(data["dns_provider"]),
      dns_options: parse_dns_options(data["dns_options"]),
      acme_provider: parse_acme_provider(data["acme_provider"]),
      acme_options: parse_acme_options(data["acme_options"]),
      importer: parse_importer(data["importer"]),
      importer_options: parse_importer_options(data["importer_options"])
    }
  end

  defp parse_dns_provider("route53"), do: Foundation.Certificates.DNSProvider.Route53
  defp parse_dns_provider("cloudflare"), do: Foundation.Certificates.DNSProvider.Cloudflare
  defp parse_dns_provider(provider), do: raise("DNS provider #{provider} not supported")

  defp parse_dns_options(nil), do: nil

  defp parse_dns_options(opts) do
    %Foundation.Yaml.Certificate.DnsOptions{
      ttl: opts["ttl"] || @default_certificate_dns_ttl,
      zone: opts["zone"],
      api_token: opts["api_token"]
    }
  end

  defp parse_acme_provider("lets_encrypt"), do: Foundation.Certificates.ACMEProvider.LetsEncrypt
  defp parse_acme_provider(provider), do: raise("ACME provider #{provider} not supported")

  defp parse_acme_options(nil), do: nil

  defp parse_acme_options(opts) do
    %Foundation.Yaml.Certificate.AcmeOptions{
      contact_email: opts["contact_email"],
      url: opts["url"] || @default_certificate_acme_client_url,
      key_size: opts["key_size"] || @default_certificate_acme_key_size,
      propagation_timeout_ms:
        opts["propagation_timeout_ms"] || @default_certificate_acme_propagation_timeout_ms,
      check_interval_ms: opts["check_interval_ms"] || @default_certificate_acme_check_interval_ms
    }
  end

  defp parse_importer("route53"), do: Foundation.Certificates.Importer.Route53
  defp parse_importer(importer), do: raise("Importer #{importer} not supported")

  defp parse_importer_options(nil), do: nil

  defp parse_importer_options(opts) do
    %Foundation.Yaml.Certificate.ImporterOptions{
      certificate_arn: opts["certificate_arn"]
    }
  end

  defp parse_notifications(nil), do: []

  defp parse_notifications(notifications) do
    Enum.map(notifications, &parse_notification/1)
  end

  defp parse_notification(data) do
    %Foundation.Yaml.Notification{
      adapter: notification_adapter(data["adapter"]),
      url: data["url"],
      enabled: data["enabled"] != false,
      events: parse_notification_events(data["events"] || []),
      options: parse_notification_options(data["options"])
    }
  end

  defp parse_notification_options(nil), do: %Foundation.Yaml.Notification.Options{}

  defp parse_notification_options(opts) do
    %Foundation.Yaml.Notification.Options{
      routing_key: opts["routing_key"],
      username: opts["username"],
      icon_emoji: opts["icon_emoji"]
    }
  end

  defp notification_adapter("webhook"), do: Foundation.Notifications.Webhook
  defp notification_adapter("slack"), do: Foundation.Notifications.Slack
  defp notification_adapter("pagerduty"), do: Foundation.Notifications.PagerDuty
  defp notification_adapter(adapter), do: raise("Notification adapter #{adapter} not supported")

  @valid_notification_events ~w(
    crash_restart
    deployment_started
    deployment_complete
    watchdog_threshold_exceeded
    watchdog_threshold_warning
    certificate_renewed
    certificate_valid
    certificate_failed
    deployment_shutdown
    config_changed
    config_change_applied
  )

  defp parse_notification_events(events) do
    Enum.map(events, &parse_notification_event/1)
  end

  defp parse_notification_event(event) when event in @valid_notification_events, do: event
  defp parse_notification_event(event), do: raise("Unknown notification event: #{event}")
end
