defmodule Deployer.Status do
  @moduledoc """
  This module will provide status abstraction
  """

  alias Deployer.Release

  defmodule Version do
    @moduledoc """
    Structure to handle the application version
    """
    @type t :: %__MODULE__{
            version: String.t() | nil,
            hash: String.t() | nil,
            pre_commands: list(),
            node: node() | nil,
            deployment: :full_deployment | :hot_upgrade,
            inserted_at: NaiveDateTime.t()
          }

    @derive Jason.Encoder

    defstruct version: nil,
              hash: nil,
              pre_commands: [],
              node: nil,
              deployment: :full_deployment,
              inserted_at: nil
  end

  @type t :: %__MODULE__{
          name: String.t() | nil,
          sname: String.t() | nil,
          node: node() | nil,
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
          language: String.t(),
          manual_version: Deployer.Status.Version.t() | nil
        }

  defstruct name: nil,
            sname: nil,
            node: nil,
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
            language: "elixir",
            manual_version: nil

  @behaviour Deployer.Status.Adapter

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
  Retrieve the current monitored app name
  """
  @impl true
  @spec monitored_app_name() :: String.t()
  def monitored_app_name, do: default().monitored_app_name()

  @doc """
  Retrieve the current monitored app language
  """
  @impl true
  @spec monitored_app_lang() :: String.t()
  def monitored_app_lang, do: default().monitored_app_lang()

  @doc """
  Retrieve the current version set for the monitored application
  """
  @impl true
  @spec current_version(node()) :: String.t() | nil
  def current_version(node), do: default().current_version(node)

  @doc """
  Retrieve the current version map set for the monitored application
  """
  @impl true
  @spec current_version_map(node()) :: Deployer.Status.Version.t()
  def current_version_map(node), do: default().current_version_map(node)

  @doc """
  Subscribe to receive status update
  """
  @impl true
  @spec subscribe() :: :ok
  def subscribe, do: default().subscribe()

  @doc """
  Set the current version map
  """
  @impl true
  @spec set_current_version_map(node(), Release.Version.t(), Keyword.t()) :: :ok
  def set_current_version_map(node, release, attrs),
    do: default().set_current_version_map(node, release, attrs)

  @doc """
  Add a ghosted version in the list
  """
  @impl true
  @spec add_ghosted_version(Deployer.Status.Version.t()) :: {:ok, list()}
  def add_ghosted_version(version_map), do: default().add_ghosted_version(version_map)

  @doc """
  Retrieve the ghosted version list
  """
  @impl true
  @spec ghosted_version_list :: list()
  def ghosted_version_list, do: default().ghosted_version_list()

  @doc """
  Retrieve the history version list
  """
  @impl true
  @spec history_version_list :: list()
  def history_version_list, do: default().history_version_list()

  @doc """
  Retrieve the history version list by node
  """
  @impl true
  @spec history_version_list(node() | binary()) :: list()
  def history_version_list(node), do: default().history_version_list(node)

  @doc """
  This function clears the service new path, so it can download and unpack
  a new release
  """
  @impl true
  @spec clear_new(node()) :: :ok
  def clear_new(node), do: default().clear_new(node)

  @doc """
  This function removes the previous service path and move the current
  to previous and new to current.
  """
  @impl true
  @spec update(node()) :: :ok
  def update(node), do: default().update(node)

  @doc """
  Set the configuration mode
  """
  @impl true
  @spec set_mode(:automatic | :manual, String.t()) :: {:ok, map()}
  def set_mode(mode, version), do: default().set_mode(mode, version)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
