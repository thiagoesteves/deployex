defmodule Foundation.Config.Upgradable do
  @moduledoc """
  Defines the subset of Deployex configuration that can be upgraded at runtime.

  Only includes fields that are safe to modify without requiring a full system restart.
  Fields like account_name, hostname, and credentials are intentionally excluded as
  they require system-level changes.
  """

  require Logger

  alias Foundation.Yaml

  defstruct deploy_rollback_timeout_ms: nil,
            deploy_schedule_interval_ms: nil,
            logs_retention_time_ms: nil,
            metrics_retention_time_ms: nil,
            monitoring: [],
            applications: [],
            config_checksum: nil

  @type t :: %__MODULE__{
          deploy_rollback_timeout_ms: non_neg_integer() | nil,
          deploy_schedule_interval_ms: non_neg_integer() | nil,
          logs_retention_time_ms: non_neg_integer() | nil,
          metrics_retention_time_ms: non_neg_integer() | nil,
          monitoring: [{atom(), Yaml.Monitoring.t()}] | [],
          applications: [Yaml.Application.t()] | [],
          config_checksum: String.t() | nil
        }

  @doc """
  Extracts upgradable fields from a full YAML configuration.
  """
  @spec from_yaml(Yaml.t()) :: t()
  def from_yaml(%Yaml{} = config) do
    %__MODULE__{
      deploy_rollback_timeout_ms: config.deploy_rollback_timeout_ms,
      deploy_schedule_interval_ms: config.deploy_schedule_interval_ms,
      logs_retention_time_ms: config.logs_retention_time_ms,
      metrics_retention_time_ms: config.metrics_retention_time_ms,
      monitoring: config.monitoring,
      applications: config.applications,
      config_checksum: config.config_checksum
    }
  end

  @doc """
  Loads upgradable configuration from application environment.
  """
  @spec from_app_env() :: t()
  def from_app_env do
    %__MODULE__{
      deploy_rollback_timeout_ms: Application.get_env(:foundation, :deploy_rollback_timeout_ms),
      deploy_schedule_interval_ms: Application.get_env(:foundation, :deploy_schedule_interval_ms),
      logs_retention_time_ms: Application.get_env(:foundation, :logs_retention_time_ms),
      metrics_retention_time_ms: Application.get_env(:observer_web, :data_retention_period),
      monitoring: Application.get_env(:foundation, :monitoring, []),
      applications: Application.get_env(:foundation, :applications, []),
      config_checksum: Application.get_env(:foundation, :config_checksum)
    }
  end
end
