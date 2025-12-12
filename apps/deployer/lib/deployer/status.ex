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
          replicas: non_neg_integer(),
          deploy_rollback_timeout_ms: non_neg_integer(),
          deploy_schedule_interval_ms: non_neg_integer(),
          otp: :connected | :not_connected,
          tls: :supported | :not_supported,
          last_deployment: :full_deployment | :hot_upgrade,
          status: :idle | :running | :starting,
          crash_restart_count: non_neg_integer(),
          force_restart_count: non_neg_integer(),
          uptime: String.t() | nil,
          latest_release: Github.Release.t(),
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
            replicas: 0,
            deploy_rollback_timeout_ms: 0,
            deploy_schedule_interval_ms: 0,
            otp: :not_connected,
            tls: :not_supported,
            last_deployment: :full_deployment,
            status: :idle,
            crash_restart_count: 0,
            force_restart_count: 0,
            uptime: nil,
            latest_release: %Github.Release{},
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
  @spec current_version(sname :: String.t()) :: String.t() | nil
  def current_version(sname), do: default().current_version(sname)

  @doc """
  Retrieve the current version map set for the monitored application
  """
  @impl true
  @spec current_version_map(sname :: String.t() | nil) :: Catalog.Version.t()
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
  @spec set_current_version_map(
          sname :: String.t(),
          release :: Release.Version.t(),
          attrs :: Keyword.t()
        ) :: :ok
  def set_current_version_map(sname, release, attrs),
    do: default().set_current_version_map(sname, release, attrs)

  @doc """
  Add a ghosted version in the list
  """
  @impl true
  @spec add_ghosted_version(version_map :: Catalog.Version.t()) :: {:ok, list()}
  def add_ghosted_version(version_map), do: default().add_ghosted_version(version_map)

  @doc """
  Retrieve the ghosted version list
  """
  @impl true
  @spec ghosted_version_list(name :: String.t()) :: list()
  def ghosted_version_list(name), do: default().ghosted_version_list(name)

  @doc """
  Retrieve the history version list by name
  """
  @impl true
  @spec history_version_list(name :: String.t(), options :: Keyword.t()) :: list()
  def history_version_list(name, options), do: default().history_version_list(name, options)

  @doc """
  Retrieve the list of installed apps by name
  """
  @impl true
  @spec list_installed_apps(name :: String.t()) :: list()
  def list_installed_apps(name), do: default().list_installed_apps(name)

  @doc """
  This function removes the previous service path and move the current
  to previous and new to current.
  """
  @impl true
  @spec update(sname :: String.t()) :: :ok
  def update(sname), do: default().update(sname)

  @doc """
  Set the configuration mode
  """
  @impl true
  @spec set_mode(name :: String.t(), mode :: :automatic | :manual, version :: String.t()) ::
          {:ok, map()}
  def set_mode(name, mode, version), do: default().set_mode(name, mode, version)

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp default, do: Application.fetch_env!(:deployer, __MODULE__)[:adapter]
end
