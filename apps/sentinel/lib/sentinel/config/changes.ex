defmodule Sentinel.Config.Changes do
  @moduledoc false

  @type(apply_strategy :: :immediate, :next_deploy, :full_deploy)
  @type numeric_change :: %{old: number(), new: number(), apply_strategy: apply_strategy()}
  @type string_change :: %{old: String.t(), new: String.t(), apply_strategy: apply_strategy()}
  @type list_change :: %{old: list(), new: list(), apply_strategy: apply_strategy()}

  @type app_diff :: %{
          :language => string_change,
          optional(:replicas) => numeric_change,
          optional(:deploy_rollback_timeout_ms) => numeric_change,
          optional(:deploy_schedule_interval_ms) => numeric_change,
          optional(:replica_ports) => list_change,
          optional(:env) => list_change,
          optional(:monitoring) => list_change
        }

  @type app_status ::
          %{status: :added, config: any(), apply_strategies: list(apply_strategy())}
          | %{status: :removed, config: any(), apply_strategies: list(apply_strategy())}
          | %{status: :modified, changes: app_diff(), apply_strategies: list(apply_strategy())}

  @type summary :: %{
          optional(:logs_retention_time_ms) => numeric_change(),
          optional(:metrics_retention_time_ms) => numeric_change(),
          optional(:monitoring) => list_change(),
          optional(:applications) => %{
            old: [Foundation.Yaml.Application.t()],
            new: [Foundation.Yaml.Application.t()],
            details: %{String.t() => app_status}
          }
        }

  @type t :: %__MODULE__{
          summary: summary() | %{},
          timestamp: DateTime.t() | nil,
          changes_count: non_neg_integer()
        }

  defstruct summary: %{},
            timestamp: nil,
            changes_count: 0
end
