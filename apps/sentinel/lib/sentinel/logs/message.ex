defmodule Sentinel.Logs.Message do
  @moduledoc """
  Structure to handle the log event
  """
  @type t :: %__MODULE__{
          timestamp: non_neg_integer(),
          log: nil | String.t()
        }

  defstruct timestamp: nil,
            log: nil
end
