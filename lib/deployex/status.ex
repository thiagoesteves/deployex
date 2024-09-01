defmodule Deployex.Status do
  @moduledoc """
  This module will provide status abstraction
  """

  alias Deployex.Release

  defmodule Version do
    @moduledoc """
    Structure to handle the application version
    """
    @type t :: %__MODULE__{
            version: String.t() | nil,
            hash: String.t() | nil,
            pre_commands: list(),
            instance: integer(),
            deployment: :full_deployment | :hot_upgrade,
            deploy_ref: String.t() | nil,
            inserted_at: NaiveDateTime.t()
          }

    @derive Jason.Encoder

    defstruct version: nil,
              hash: nil,
              pre_commands: [],
              instance: 1,
              deployment: :full_deployment,
              deploy_ref: nil,
              inserted_at: nil
  end

  @type t :: %__MODULE__{
          name: String.t() | nil,
          instance: integer(),
          version: nil,
          otp: :connected | :not_connected,
          tls: :supported | :not_supported,
          last_deployment: :full_deployment | :hot_upgrade,
          supervisor: boolean(),
          status: :idle | :running | :starting,
          crash_restart_count: integer(),
          force_restart_count: integer(),
          uptime: String.t() | nil,
          last_ghosted_version: String.t() | nil,
          mode: :automatic | :manual,
          manual_version: Deployex.Status.Version.t() | nil
        }

  defstruct name: nil,
            instance: 0,
            version: nil,
            otp: :not_connected,
            tls: :not_supported,
            last_deployment: :full_deployment,
            supervisor: true,
            status: :idle,
            crash_restart_count: 0,
            force_restart_count: 0,
            uptime: nil,
            last_ghosted_version: nil,
            mode: :automatic,
            manual_version: nil

  @behaviour Deployex.Status.Adapter

  def default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Retrieve the current monitoring status of the gen_server
  """
  @impl true
  @spec monitoring() :: {:ok, list()} | {:error, :rescued}
  def monitoring, do: default().monitoring()

  @doc """
  Retrieve the current version set for the monitored application
  """
  @impl true
  @spec current_version(integer()) :: String.t() | nil
  def current_version(instance), do: default().current_version(instance)

  @doc """
  Retrieve the current version map set for the monitored application
  """
  @impl true
  @spec current_version_map(integer()) :: Deployex.Status.Version.t()
  def current_version_map(instance), do: default().current_version_map(instance)

  @doc """
  Retrieve the topic in which the module is publishing its status
  """
  @impl true
  @spec listener_topic() :: String.t()
  def listener_topic, do: default().listener_topic

  @doc """
  Set the current version map
  """
  @impl true
  @spec set_current_version_map(integer(), Release.Version.t(), Keyword.t()) :: :ok
  def set_current_version_map(instance, release, attrs),
    do: default().set_current_version_map(instance, release, attrs)

  @doc """
  Add a ghosted version in the list
  """
  @impl true
  @spec add_ghosted_version(Deployex.Status.Version.t()) :: {:ok, list()}
  def add_ghosted_version(version_map), do: default().add_ghosted_version(version_map)

  @doc """
  Retrieve the ghosted version list
  """
  @impl true
  @spec ghosted_version_list :: list()
  def ghosted_version_list, do: default().ghosted_version_list

  @doc """
  Retrieve the history version list
  """
  @impl true
  @spec history_version_list :: list()
  def history_version_list, do: default().history_version_list

  @doc """
  Retrieve the history version list by instance
  """
  @impl true
  @spec history_version_list(integer() | binary()) :: list()
  def history_version_list(instance), do: default().history_version_list(instance)

  @doc """
  This function clears the service new path, so it can download and unpack
  a new release
  """
  @impl true
  @spec clear_new(integer()) :: :ok
  def clear_new(instance), do: default().clear_new(instance)

  @doc """
  This function removes the previous service path and move the current
  to previous and new to current.
  """
  @impl true
  @spec update(integer()) :: :ok
  def update(instance), do: default().update(instance)

  @doc """
  Retrieve the current mode configuration
  """
  @impl true
  @spec mode() :: {:ok, map()} | {:error, :rescued}
  def mode, do: default().mode()

  @doc """
  Set the configuration mode
  """
  @impl true
  @spec set_mode(:automatic | :manual, String.t()) :: {:ok, map()}
  def set_mode(mode, version), do: default().set_mode(mode, version)
end
