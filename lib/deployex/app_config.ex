defmodule Deployex.AppConfig do
  @moduledoc """
  This module contains all paths for services and also initialize the directories
  """

  alias Deployex.AppConfig
  @deployex_instance 0

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @doc """
  Ensure all directories are initialised
  """
  @spec init() :: :ok
  def init do
    create_storage_folder = fn instance ->
      File.mkdir_p!("#{base_path()}/storage/#{monitored_app()}/#{instance}")
    end

    AppConfig.replicas_list()
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
  This function return the number of replicas configured

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.replicas == 3
  """
  def replicas, do: Application.get_env(:deployex, :replicas)

  @doc """
  This function return a list with all replicas that needs to be
  monitored

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.replicas_list == [1, 2, 3]
  """
  def replicas_list, do: Enum.to_list(1..replicas())

  @doc """
  Return the app name that will be monitored

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.monitored_app() == "testapp"
  """
  @spec monitored_app() :: binary()
  def monitored_app, do: Application.fetch_env!(:deployex, :monitored_app_name)

  @doc """
  Return the monitored app phoenix port

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.phx_start_port() == 4444
  """
  @spec phx_start_port() :: integer()
  def phx_start_port, do: Application.get_env(:deployex, :monitored_app_phx_start_port)

  @doc """
  Return the path for the stdout log file

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.stdout_path(0) == "/var/log/deployex/deployex-stdout.log"
    ...> assert AppConfig.stdout_path(1) == "/tmp/myphoenixapp/testapp/testapp-1-stdout.log"
    ...> assert AppConfig.stdout_path(2) == "/tmp/myphoenixapp/testapp/testapp-2-stdout.log"
    ...> assert AppConfig.stdout_path(3) == "/tmp/myphoenixapp/testapp/testapp-3-stdout.log"
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

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.stderr_path(0) == "/var/log/deployex/deployex-stderr.log"
    ...> assert AppConfig.stderr_path(1) == "/tmp/myphoenixapp/testapp/testapp-1-stderr.log"
    ...> assert AppConfig.stderr_path(2) == "/tmp/myphoenixapp/testapp/testapp-2-stderr.log"
    ...> assert AppConfig.stderr_path(3) == "/tmp/myphoenixapp/testapp/testapp-3-stderr.log"
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

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.sname(0) == "testapp-0"
    ...> assert AppConfig.sname(1) == "testapp-1"
    ...> assert AppConfig.sname(2) == "testapp-2"
    ...> assert AppConfig.sname(3) == "testapp-3"
  """
  @spec sname(integer()) :: String.t()
  def sname(instance), do: "#{monitored_app()}-#{instance}"

  @doc """
  Retrieve the bin path for the respective instance (current)

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.bin_path(0) == "/opt/deployex/bin/deployex"
    ...> assert AppConfig.bin_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/current/bin/testapp"
    ...> assert AppConfig.bin_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/current/bin/testapp"
    ...> assert AppConfig.bin_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/current/bin/testapp"
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

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.base_path() == "/tmp/deployex/test/varlib"
  """
  @spec base_path() :: any()
  def base_path, do: Application.fetch_env!(:deployex, :base_path)

  @doc """
  Path for retrieving the new app data

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.new_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/new"
    ...> assert AppConfig.new_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/new"
    ...> assert AppConfig.new_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/new"
    ...> assert AppConfig.new_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/new"
  """
  @spec new_path(integer()) :: binary()
  def new_path(instance), do: "#{service_path()}/#{instance}/new"

  @doc """
  Path where the app will be running from

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.current_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/current"
    ...> assert AppConfig.current_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/current"
    ...> assert AppConfig.current_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/current"
    ...> assert AppConfig.current_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/current"
  """
  @spec current_path(integer()) :: binary()
  def current_path(instance), do: "#{service_path()}/#{instance}/current"

  @doc """
  Path to move the previous app files

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.previous_path(0) == "/tmp/deployex/test/varlib/service/testapp/0/previous"
    ...> assert AppConfig.previous_path(1) == "/tmp/deployex/test/varlib/service/testapp/1/previous"
    ...> assert AppConfig.previous_path(2) == "/tmp/deployex/test/varlib/service/testapp/2/previous"
    ...> assert AppConfig.previous_path(3) == "/tmp/deployex/test/varlib/service/testapp/3/previous"
  """
  @spec previous_path(integer()) :: binary()
  def previous_path(instance), do: "#{service_path()}/#{instance}/previous"

  @doc """
  Path to the current version json file

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.current_version_path(0) == "/tmp/deployex/test/varlib/storage/testapp/0/current.json"
    ...> assert AppConfig.current_version_path(1) == "/tmp/deployex/test/varlib/storage/testapp/1/current.json"
    ...> assert AppConfig.current_version_path(2) == "/tmp/deployex/test/varlib/storage/testapp/2/current.json"
    ...> assert AppConfig.current_version_path(3) == "/tmp/deployex/test/varlib/storage/testapp/3/current.json"
  """
  @spec current_version_path(integer()) :: binary()
  def current_version_path(instance),
    do: "#{base_path()}/storage/#{monitored_app()}/#{instance}/current.json"

  @doc """
  Path to the history version json file

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.history_version_path == "/tmp/deployex/test/varlib/storage/testapp/0/history.json"
  """
  @spec history_version_path :: binary()
  def history_version_path,
    do: "#{base_path()}/storage/#{monitored_app()}/#{@deployex_instance}/history.json"

  @doc """
  Path to the ghosted version json file

  ## Examples

    iex> alias Deployex.AppConfig
    ...> assert AppConfig.ghosted_version_path == "/tmp/deployex/test/varlib/storage/testapp/0/ghosted.json"
  """
  @spec ghosted_version_path :: binary()
  def ghosted_version_path,
    do: "#{base_path()}/storage/#{monitored_app()}/#{@deployex_instance}/ghosted.json"

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp service_path, do: "#{base_path()}/service/#{monitored_app()}"
  defp log_path, do: Application.fetch_env!(:deployex, :monitored_app_log_path)
end
