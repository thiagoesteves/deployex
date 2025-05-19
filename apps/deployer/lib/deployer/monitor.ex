defmodule Deployer.Monitor do
  @moduledoc """
  This module will provide module abstraction
  """

  @behaviour Deployer.Monitor.Adapter

  @type t :: %__MODULE__{
          current_pid: pid() | nil,
          sname: String.t() | nil,
          port: non_neg_integer(),
          language: String.t() | nil,
          status: :idle | :running | :starting,
          crash_restart_count: integer(),
          force_restart_count: integer(),
          start_time: nil | integer(),
          timeout_app_ready: integer(),
          retry_delay_pre_commands: integer()
        }

  defstruct current_pid: nil,
            sname: nil,
            port: 0,
            language: nil,
            status: :idle,
            crash_restart_count: 0,
            force_restart_count: 0,
            start_time: nil,
            timeout_app_ready: nil,
            retry_delay_pre_commands: nil

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Starts monitor service for an specific sname
  """
  @impl true
  @spec start_service(String.t(), String.t(), non_neg_integer(), list()) ::
          {:ok, pid} | {:error, pid(), :already_started}
  def start_service(sname, language, port, options \\ []) do
    default().start_service(sname, language, port, options)
  end

  @doc """
  Stops a monitor service fo an specific sname
  """
  @impl true
  @spec stop_service(String.t() | nil) :: :ok
  def stop_service(sname), do: default().stop_service(sname)

  @doc """
  This function forces a restart of the application
  """
  @impl true
  @spec restart(String.t()) :: :ok | {:error, :application_is_not_running}
  def restart(sname), do: default().restart(sname)

  @doc """
  Retrieve the expected current version for the application
  """
  @impl true
  @spec state(String.t()) :: Deployer.Monitor.t()
  def state(sname), do: default().state(sname)

  @doc """
  Download and unpack the application
  """
  @impl true
  @spec run_pre_commands(String.t(), list(), :new | :current) ::
          {:ok, list()} | {:error, :rescued}
  def run_pre_commands(sname, pre_commands, app_bin_path),
    do: default().run_pre_commands(sname, pre_commands, app_bin_path)

  @doc """
  Return the global name used by this module to register the process
  """
  @impl true
  @spec list() :: list()
  def list, do: default().list()

  @doc """
  Subscribe to Monitor New deploy Event
  """
  @impl true
  @spec subscribe_new_deploy() :: :ok
  def subscribe_new_deploy, do: default().subscribe_new_deploy()

  @doc """
  Return the global name used by this module to register the process
  """
  @impl true
  @spec global_name(String.t()) :: map()
  def global_name(sname), do: default().global_name(sname)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
