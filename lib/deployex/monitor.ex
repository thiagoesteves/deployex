defmodule Deployex.Monitor do
  @moduledoc """
  This module will provide module abstraction
  """

  @behaviour Deployex.Monitor.Adapter

  @type t :: %__MODULE__{
          current_pid: pid() | nil,
          instance: integer() | nil,
          status: :idle | :running | :starting,
          crash_restart_count: integer(),
          force_restart_count: integer(),
          start_time: nil | integer(),
          deploy_ref: :init | reference(),
          timeout_app_ready: integer(),
          retry_delay_pre_commands: integer()
        }

  defstruct current_pid: nil,
            instance: nil,
            status: :idle,
            crash_restart_count: 0,
            force_restart_count: 0,
            start_time: nil,
            deploy_ref: :init,
            timeout_app_ready: nil,
            retry_delay_pre_commands: nil

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
  This function forces a restart of the application
  """
  @impl true
  @spec restart(integer()) :: :ok | {:error, :application_is_not_running}
  def restart(instance), do: default().restart(instance)

  @doc """
  Retrieve the expected current version for the application
  """
  @impl true
  @spec state(integer()) :: Deployex.Monitor.t()
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
