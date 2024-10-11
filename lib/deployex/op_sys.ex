defmodule Deployex.OpSys do
  @moduledoc """
  This module will provide operational system abstraction
  """

  @behaviour Deployex.OpSys.Adapter

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Run the passed commands and link the process with the genserver calling
  gen_server for supervision
  """
  @impl true
  @spec run_link(String.t(), list()) ::
          {:ok, any()} | {:ok, pid(), integer()} | {:error, any()}
  def run_link(command, options), do: default().run_link(command, options)

  @doc """
  Run the passed commands
  """
  @impl true
  @spec run(String.t(), list()) ::
          {:ok, any()} | {:ok, pid(), integer()} | {:error, any()}
  def run(command, options), do: default().run(command, options)

  @doc """
  Stop the passed process pid
  """
  @impl true
  @spec stop(integer()) :: :ok | {:error, any()}
  def stop(process_pid), do: default().stop(process_pid)

  @doc """
  Send a message to the passed process pid
  """
  @impl true
  @spec send(integer(), String.t()) :: :ok
  def send(process_pid, message), do: default().send(process_pid, message)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]
end
