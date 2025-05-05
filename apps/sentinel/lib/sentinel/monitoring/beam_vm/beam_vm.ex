defmodule Sentinel.Monitoring.BeamVm do
  @moduledoc """
  Structure to handle the Beam VM statistics
  """
  @type t :: %__MODULE__{
          source_node: nil | atom(),
          statistics: nil | map()
        }

  defstruct source_node: nil,
            statistics: nil
end
