defmodule Deployex.Terminal do
  @moduledoc """
  This module will provide terminal abstraction
  """

  @type t :: %__MODULE__{
          commands: String.t(),
          metadata: any(),
          myself: pid() | nil,
          process: pid() | nil,
          msg_sequence: integer(),
          target: pid() | nil,
          instance: non_neg_integer(),
          status: :open | :closed,
          message: String.t() | nil,
          options: list(),
          timeout_session: nil | integer() | :infinity
        }

  defstruct commands: nil,
            metadata: nil,
            myself: nil,
            process: nil,
            msg_sequence: 0,
            instance: 0,
            target: nil,
            status: :open,
            message: nil,
            options: [],
            timeout_session: nil

  ### ==========================================================================
  ### Public API
  ### ==========================================================================

  @doc """
  Starts a new Terminal server instance
  """
  @spec new(t()) :: {:ok, pid} | {:error, pid(), :already_started}
  def new(%__MODULE__{} = attrs), do: __MODULE__.Supervisor.new(attrs)

  @doc """
  Asynchronously terminates a Terminal based on the passed pid
  """
  @spec async_terminate(pid()) :: :ok
  def async_terminate(pid), do: __MODULE__.Server.async_terminate(pid)
end
