defmodule Sentinel.Watchdog.Data do
  @moduledoc """
  Structure to handle the Application statistics
  """
  @type t :: %__MODULE__{
          current: nil | non_neg_integer(),
          limit: nil | non_neg_integer()
        }

  defstruct current: nil,
            limit: nil
end
