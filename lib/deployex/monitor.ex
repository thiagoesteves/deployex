defmodule Deployex.Monitor do
  @moduledoc """
  This module will provide module abstraction
  """

  @behaviour Deployex.Monitor.Adapter

  def default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Starts monitor service for an specific instance
  """
  @impl true
  @spec start_service(integer(), reference(), list()) ::
          {:ok, pid} | {:error, pid(), :already_started}
  def start_service(instance, deploy_ref, options \\ []) do
    default().start_service(instance, deploy_ref, options)
  end

  @doc """
  Stops a monitor service fo an specific instance
  """
  @impl true
  @spec stop_service(integer()) :: :ok
  def stop_service(instance), do: default().stop_service(instance)

  @doc """
  Retrieve the expected current version for the application
  """
  @impl true
  @spec state(integer()) :: {:ok, map()} | {:error, :rescued}
  def state(instance), do: default().state(instance)

  @doc """
  Download and unpack the application
  """
  @impl true
  @spec run_pre_commands(integer(), list(), :new | :current) ::
          {:ok, list()} | {:error, :rescued}
  def run_pre_commands(instance, pre_commands, app_bin_path),
    do: default().run_pre_commands(instance, pre_commands, app_bin_path)

  @doc """
  Return the global name used by this module to register the precesses
  """
  @impl true
  @spec global_name(integer()) :: map()
  def global_name(instance), do: default().global_name(instance)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
