defmodule Sentinel.Watchdog.Data do
  @moduledoc """
  Structure to handle the Application statistics
  """
  @type t :: %__MODULE__{
          restart_enabled: boolean,
          warning_log: boolean,
          warning_threshold: nil | non_neg_integer(),
          restart_threshold: nil | non_neg_integer()
        }

  defstruct restart_enabled: true,
            warning_log: false,
            warning_threshold: 10,
            restart_threshold: 20
end
