defmodule Foundation.Config.Changes do
  @moduledoc false

  @type numeric_change :: %{old: number(), new: number()}
  @type string_change :: %{old: String.t(), new: String.t()}
  @type list_change :: %{old: list(), new: list()}

  @type app_diff :: %{
          optional(:language) => string_change,
          optional(:replicas) => numeric_change,
          optional(:deploy_rollback_timeout_ms) => numeric_change,
          optional(:deploy_schedule_interval_ms) => numeric_change,
          optional(:replica_ports) => list_change,
          optional(:env) => list_change,
          optional(:monitoring) => %{old: any(), new: any()}
        }

  @type app_status ::
          %{status: :added, config: any()}
          | %{status: :removed, config: any()}
          | %{status: :modified, changes: app_diff}

  @type summary :: %{
          optional(:logs_retention_time_ms) => numeric_change,
          optional(:metrics_retention_time_ms) => numeric_change,
          optional(:monitoring) => %{old: list(), new: list()},
          optional(:applications) => %{
            old: [String.t()],
            new: [String.t()],
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
