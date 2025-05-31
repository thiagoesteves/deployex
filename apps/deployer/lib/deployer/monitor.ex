defmodule Deployer.Monitor do
  @moduledoc """
  This module will provide module abstraction
  """

  alias Deployer.Monitor
  alias Foundation.Catalog

  @behaviour Monitor.Adapter

  @type t :: %__MODULE__{
          current_pid: pid() | nil,
          name: String.t() | nil,
          sname: String.t() | nil,
          port: non_neg_integer(),
          env: list(),
          language: String.t() | nil,
          status: :idle | :running | :starting,
          crash_restart_count: integer(),
          force_restart_count: integer(),
          start_time: nil | integer(),
          timeout_app_ready: integer(),
          retry_delay_pre_commands: integer()
        }

  defstruct current_pid: nil,
            name: nil,
            sname: nil,
            port: 0,
            env: nil,
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
  Starts monitor service for an specific service
  """
  @impl true
  @spec start_service(Monitor.Service.t()) :: {:ok, pid} | {:error, pid(), :already_started}
  def start_service(%Monitor.Service{} = service) do
    default().start_service(service)
  end

  @doc """
  Stops a monitor service for an specific name/sname
  """
  @impl true
  @spec stop_service(String.t() | nil, String.t() | nil) :: :ok
  def stop_service(name, sname), do: default().stop_service(name, sname)

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
  @spec run_pre_commands(String.t(), list(), Monitor.Adapter.bin_path()) ::
          {:ok, list()} | {:error, :rescued}
  def run_pre_commands(sname, pre_commands, app_bin_path),
    do: default().run_pre_commands(sname, pre_commands, app_bin_path)

  @doc """
  Return a list of all snames that are being handled
  """
  @impl true
  @spec list() :: list()
  def list, do: default().list()

  @impl true
  @spec list(Keyword.t()) :: list()
  def list(options), do: default().list(options)

  @doc """
  Subscribe to Monitor New deploy Event
  """
  @impl true
  @spec subscribe_new_deploy() :: :ok
  def subscribe_new_deploy, do: default().subscribe_new_deploy()

  @doc """
  Initialize one monitor supervisor per monitored application
  """
  @spec initialize_monitor_supervisor :: :ok
  def initialize_monitor_supervisor do
    Enum.each(Catalog.applications(), fn %{name: name} ->
      {:ok, _pid} = Monitor.Supervisor.create_monitor_supervisor(name)
    end)

    :ok
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
