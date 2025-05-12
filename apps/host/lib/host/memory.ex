defmodule Host.Memory do
  @moduledoc """
  This module will provide host memory information
  """

  alias Host.Memory.Server

  @type t :: %__MODULE__{
          host: String.t(),
          source_node: nil | node(),
          description: String.t(),
          memory_free: nil | non_neg_integer(),
          memory_total: nil | non_neg_integer(),
          cpu: nil | non_neg_integer(),
          cpus: nil | non_neg_integer()
        }

  defstruct host: "",
            source_node: nil,
            description: "",
            memory_free: nil,
            memory_total: nil,
            cpu: nil,
            cpus: nil

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @spec subscribe() :: :ok | {:error, any()}
  def subscribe, do: Server.subscribe()

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
