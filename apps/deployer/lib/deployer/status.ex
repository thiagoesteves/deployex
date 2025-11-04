defmodule Deployer.Status do
  @moduledoc """
  This module will provide status abstraction
  """

  alias Deployer.Github
  alias Deployer.Release
  alias Foundation.Catalog

  @type t :: %__MODULE__{
          name: String.t() | nil,
          sname: String.t() | nil,
          node: node() | nil,
          ports: [],
          version: nil,
          language: String.t(),
          otp: :connected | :not_connected,
          tls: :supported | :not_supported,
          last_deployment: :full_deployment | :hot_upgrade,
          status: :idle | :running | :starting,
          crash_restart_count: integer(),
          force_restart_count: integer(),
          uptime: String.t() | nil,
          latest_release: Github.t(),
          config: map() | nil,
          # Self-referential for nested apps
          children: [t()],
          # Monitoring capabilities
          monitoring: []
        }

  defstruct name: nil,
            sname: nil,
            node: nil,
            ports: [],
            version: nil,
            language: "elixir",
            otp: :not_connected,
            tls: :not_supported,
            last_deployment: :full_deployment,
            status: :idle,
            crash_restart_count: 0,
            force_restart_count: 0,
            uptime: nil,
            latest_release: %Github{},
            config: nil,
            children: [],
            monitoring: []

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
  Retrieve the current version set for the monitored application
  """
  @impl true
  @spec current_version(String.t()) :: String.t() | nil
  def current_version(sname), do: default().current_version(sname)

  @doc """
  Retrieve the current version map set for the monitored application
  """
  @impl true
  @spec current_version_map(String.t() | nil) :: Catalog.Version.t()
  def current_version_map(sname), do: default().current_version_map(sname)

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
  @spec set_current_version_map(String.t(), Release.Version.t(), Keyword.t()) :: :ok
  def set_current_version_map(sname, release, attrs),
    do: default().set_current_version_map(sname, release, attrs)

  @doc """
  Add a ghosted version in the list
  """
  @impl true
  @spec add_ghosted_version(Catalog.Version.t()) :: {:ok, list()}
  def add_ghosted_version(version_map), do: default().add_ghosted_version(version_map)

  @doc """
  Retrieve the ghosted version list
  """
  @impl true
  @spec ghosted_version_list(String.t()) :: list()
  def ghosted_version_list(name), do: default().ghosted_version_list(name)

  @doc """
  Retrieve the history version list by name
  """
  @impl true
  @spec history_version_list(String.t(), Keyword.t()) :: list()
  def history_version_list(name, options), do: default().history_version_list(name, options)

  @doc """
  Retrieve the list of installed apps by name
  """
  @impl true
  @spec list_installed_apps(String.t()) :: list()
  def list_installed_apps(name), do: default().list_installed_apps(name)

  @doc """
  This function removes the previous service path and move the current
  to previous and new to current.
  """
  @impl true
  @spec update(String.t()) :: :ok
  def update(sname), do: default().update(sname)

  @doc """
  Set the configuration mode
  """
  @impl true
  @spec set_mode(String.t(), :automatic | :manual, String.t()) :: {:ok, map()}
  def set_mode(name, mode, version), do: default().set_mode(name, mode, version)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
