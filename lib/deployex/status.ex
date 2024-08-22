defmodule Deployex.Status do
  @moduledoc """
  This module will provide status abstraction
  """

  alias Deployex.Release

  @type deployex_version_map :: %{
          version: String.t(),
          hash: String.t(),
          instance: integer(),
          deployment: atom(),
          deploy_ref: String.t(),
          inserted_at: NaiveDateTime.t()
        }

  defstruct name: nil,
            instance: 0,
            version: nil,
            otp: nil,
            tls: :not_supported,
            last_deployment: nil,
            supervisor: false,
            status: nil,
            crash_restart_count: 0,
            uptime: nil,
            last_ghosted_version: nil

  @behaviour Deployex.Status.Adapter

  def default, do: Application.fetch_env!(:deployex, __MODULE__)[:adapter]

  ### ==========================================================================
  ### Callback function implementation
  ### ==========================================================================

  @doc """
  Retrieve the current state of the gen_server
  """
  @impl true
  @spec state() :: {:ok, map()} | {:error, :rescued}
  def state, do: default().state()

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
  @spec current_version_map(integer()) :: deployex_version_map() | nil
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
  @spec set_current_version_map(integer(), Release.version_map(), Keyword.t()) :: :ok
  def set_current_version_map(instance, release, attrs),
    do: default().set_current_version_map(instance, release, attrs)

  @doc """
  Add a ghosted version in the list
  """
  @impl true
  @spec add_ghosted_version(deployex_version_map()) :: {:ok, list()}
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

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
end
