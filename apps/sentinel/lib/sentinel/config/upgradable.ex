defmodule Sentinel.Config.Upgradable do
  @moduledoc """
  Defines the subset of Deployex configuration that can be upgraded at runtime.

  Only includes fields that are safe to modify without requiring a full system restart.
  Fields like account_name, hostname, and credentials are intentionally excluded as
  they require system-level changes. The OAuth `client_secret` is excluded for the same
  reason: it comes from the secrets provider, not from the YAML `auth` section.
  """

  alias Foundation.Yaml

  defstruct logs_retention_time_ms: nil,
            metrics_retention_time_ms: nil,
            releases_retention: nil,
            monitoring: [],
            applications: [],
            notifications: [],
            auth: nil,
            config_checksum: nil

  @type t :: %__MODULE__{
          logs_retention_time_ms: non_neg_integer() | nil,
          metrics_retention_time_ms: non_neg_integer() | nil,
          releases_retention: non_neg_integer() | nil,
          monitoring: [{atom(), Yaml.Monitoring.t()}] | [],
          applications: [Yaml.Application.t()] | [],
          notifications: [Yaml.Notification.t()] | [],
          auth: Yaml.Auth.t() | nil,
          config_checksum: String.t() | nil
        }

  @doc """
  Extracts upgradable fields from a full YAML configuration.
  """
  @spec from_yaml(Yaml.t()) :: t()
  def from_yaml(%Yaml{} = config) do
    %__MODULE__{
      logs_retention_time_ms: config.logs_retention_time_ms,
      metrics_retention_time_ms: config.metrics_retention_time_ms,
      releases_retention: config.releases_retention,
      monitoring: config.monitoring,
      applications: config.applications,
      notifications: config.notifications,
      auth: config.auth,
      config_checksum: config.config_checksum
    }
  end

  @doc """
  Loads upgradable configuration from application environment.
  """
  @spec from_app_env() :: t()
  def from_app_env do
    %__MODULE__{
      logs_retention_time_ms: Application.get_env(:foundation, :logs_retention_time_ms),
      metrics_retention_time_ms: Application.get_env(:observer_web, :data_retention_period),
      releases_retention: Application.get_env(:foundation, :releases_retention),
      monitoring: Application.get_env(:foundation, :monitoring, []),
      applications: Application.get_env(:foundation, :applications, []),
      notifications: Application.get_env(:foundation, :notifications, []),
      auth: auth_from_app_env(),
      config_checksum: Application.get_env(:foundation, :config_checksum)
    }
  end

  # The YAML `auth` section is stored in the :deployex_web env next to the client_secret. An env
  # that holds only the client_secret or the provider has no auth section.
  defp auth_from_app_env do
    config = Application.get_env(:deployex_web, DeployexWeb.OAuth, [])

    if Enum.any?([:client_id, :redirect_uri, :allowlist], &Keyword.has_key?(config, &1)) do
      %Yaml.Auth{
        provider: Keyword.get(config, :provider, DeployexWeb.OAuth.Provider.GitHub),
        client_id: Keyword.get(config, :client_id),
        redirect_uri: Keyword.get(config, :redirect_uri),
        allowlist: Keyword.get(config, :allowlist, %Yaml.Auth{}.allowlist)
      }
    end
  end
end
