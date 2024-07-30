defmodule Deployex.AppConfig do
  @moduledoc """
  This module contains all paths for services and also initialize the directories
  """

  @deployex_instance 0

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Ensure all directories are initialised
  """
  @spec init(list()) :: :ok
  def init(instances) do
    create_storage_folder = fn instance ->
      File.mkdir_p!("#{base_path()}/storage/#{instance}")
    end

    instances
    |> Enum.each(fn instance ->
      # Create the service folders (If they don't exist)
      [new_path(instance), current_path(instance), previous_path(instance)]
      |> Enum.each(&File.mkdir_p!/1)

      # Create storage folders (If they don't exist)
      create_storage_folder.(instance)

      # Create folder and Log message files (If they don't exist)
      File.mkdir_p!("#{log_path()}/#{monitored_app()}")
      File.touch(stdout_path(instance))
      File.touch(stderr_path(instance))
    end)

    # Create storage for deployex instance
    create_storage_folder.(@deployex_instance)

    :ok
  end

  @doc """
  Return the app name that will be monitored
  """
  @spec monitored_app() :: binary()
  def monitored_app, do: Application.fetch_env!(:deployex, :monitored_app_name)

  @doc """
  Return the monitored app phoenix port
  """
  @spec phx_start_port() :: integer()
  def phx_start_port, do: Application.get_env(:deployex, :monitored_app_phx_start_port)

  @doc """
  Return the path for the stdout log file
  """
  @spec stdout_path(integer()) :: binary()
  def stdout_path(@deployex_instance) do
    log_path = Application.fetch_env!(:deployex, :log_path)
    "#{log_path}/deployex-stdout.log"
  end

  def stdout_path(instance) do
    log_path = Application.fetch_env!(:deployex, :monitored_app_log_path)
    monitored_app = monitored_app()
    "#{log_path}/#{monitored_app}/#{monitored_app}-#{instance}-stdout.log"
  end

  @doc """
  Return the path for the stderr log file
  """
  @spec stderr_path(integer()) :: binary()
  def stderr_path(@deployex_instance) do
    log_path = Application.fetch_env!(:deployex, :log_path)
    "#{log_path}/deployex-stderr.log"
  end

  def stderr_path(instance) do
    log_path = Application.fetch_env!(:deployex, :monitored_app_log_path)
    monitored_app = monitored_app()
    "#{log_path}/#{monitored_app}/#{monitored_app}-#{instance}-stderr.log"
  end

  @doc """
  Return the sname of the application with the correct instance suffix
  """
  @spec sname(integer()) :: String.t()
  def sname(instance), do: "#{monitored_app()}-#{instance}"

  @doc """
  Retrieve the bin path for the respective instance (current)
  """
  @spec bin_path(integer()) :: String.t()
  def bin_path(@deployex_instance) do
    Application.fetch_env!(:deployex, :bin_path)
  end

  def bin_path(instance) do
    monitored_app = monitored_app()
    "#{current_path(instance)}/bin/#{monitored_app}"
  end

  @doc """
  Base path for the state and service data
  """
  @spec base_path() :: any()
  def base_path, do: Application.fetch_env!(:deployex, :base_path)

  @doc """
  Path for retrieving the new app data
  """
  @spec new_path(integer()) :: binary()
  def new_path(instance), do: "#{service_path()}/#{instance}/new"

  @doc """
  Path where the app will be running from
  """
  @spec current_path(integer()) :: binary()
  def current_path(instance), do: "#{service_path()}/#{instance}/current"

  @doc """
  Path to move the previous app files
  """
  @spec previous_path(integer()) :: binary()
  def previous_path(instance), do: "#{service_path()}/#{instance}/previous"

  @doc """
  Path to the current version json file
  """
  @spec current_version_path(integer()) :: binary()
  def current_version_path(instance),
    do: "#{base_path()}/storage/#{instance}/current.json"

  @doc """
  Path to the history version json file
  """
  @spec history_version_path :: binary()
  def history_version_path,
    do: "#{base_path()}/storage/#{@deployex_instance}/history.json"

  @doc """
  Path to the ghosted version json file
  """
  @spec ghosted_version_path :: binary()
  def ghosted_version_path,
    do: "#{base_path()}/storage/#{@deployex_instance}/ghosted.json"

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp service_path, do: "#{base_path()}/service/#{monitored_app()}"
  defp log_path, do: Application.fetch_env!(:deployex, :monitored_app_log_path)
end
