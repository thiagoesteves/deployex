defmodule Deployex.System do
  @moduledoc """
  This module will provide system information
  """

  alias Deployex.System.Server, as: SystemServer

  @type t :: %__MODULE__{
          host: String.t(),
          description: String.t(),
          memory_free: non_neg_integer(),
          memory_total: non_neg_integer(),
          cpu: non_neg_integer(),
          cpus: non_neg_integer()
        }

  defstruct host: "",
            description: "",
            memory_free: nil,
            memory_total: nil,
            cpu: nil,
            cpus: nil

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @spec subscribe() :: :ok | {:error, any()}
  def subscribe, do: SystemServer.subscribe()

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
