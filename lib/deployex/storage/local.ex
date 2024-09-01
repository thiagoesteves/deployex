defmodule Deployex.Storage.Local do
  @moduledoc """
  This module contains all paths for services and also initialize the directories
  """

  @behaviour Deployex.Storage.Adapter

  require Logger

  @deployex_instance 0
  @config_key_file "config.term"

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @impl true
  def init do
    replicas_list()
    |> Enum.each(fn instance ->
      # Create the service folders (If they don't exist)
      [new_path(instance), current_path(instance), previous_path(instance)]
      |> Enum.each(&File.mkdir_p!/1)

      # Create folder and Log message files (If they don't exist)
      File.mkdir_p!("#{log_path()}/#{monitored_app()}")
      File.touch(stdout_path(instance))
      File.touch(stderr_path(instance))
    end)

    # Create storage for deployex instance (If they don't exist)
    File.mkdir_p!(config_path())
    File.mkdir_p!(history_version_path())
    File.mkdir_p!(ghosted_version_path())

    :ok
  end

  @impl true
  def replicas, do: Application.get_env(:deployex, :replicas)

  @impl true
  def replicas_list, do: Enum.to_list(1..replicas())

  @impl true
  def monitored_app, do: Application.fetch_env!(:deployex, :monitored_app_name)

  @impl true
  def phx_start_port, do: Application.get_env(:deployex, :monitored_app_phx_start_port)

  @impl true
  def stdout_path(@deployex_instance) do
    log_path = Application.fetch_env!(:deployex, :log_path)
    "#{log_path}/deployex-stdout.log"
  end

  def stdout_path(instance) do
    log_path = Application.fetch_env!(:deployex, :monitored_app_log_path)
    monitored_app = monitored_app()
    "#{log_path}/#{monitored_app}/#{monitored_app}-#{instance}-stdout.log"
  end

  @impl true
  def stderr_path(@deployex_instance) do
    log_path = Application.fetch_env!(:deployex, :log_path)
    "#{log_path}/deployex-stderr.log"
  end

  def stderr_path(instance) do
    log_path = Application.fetch_env!(:deployex, :monitored_app_log_path)
    monitored_app = monitored_app()
    "#{log_path}/#{monitored_app}/#{monitored_app}-#{instance}-stderr.log"
  end

  @impl true
  def sname(instance), do: "#{monitored_app()}-#{instance}"

  @impl true
  def bin_path(@deployex_instance) do
    Application.fetch_env!(:deployex, :bin_path)
  end

  def bin_path(instance) do
    monitored_app = monitored_app()
    "#{current_path(instance)}/bin/#{monitored_app}"
  end

  @impl true
  def base_path, do: Application.fetch_env!(:deployex, :base_path)

  @impl true
  def new_path(instance), do: "#{service_path()}/#{instance}/new"

  @impl true
  def current_path(instance), do: "#{service_path()}/#{instance}/current"

  @impl true
  def previous_path(instance), do: "#{service_path()}/#{instance}/previous"

  @impl true
  def versions do
    history_version_path()
    |> list()
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  @impl true
  def versions(instance) do
    versions()
    |> Enum.filter(&(&1.instance == instance))
  end

  @impl true
  def add_version(version) do
    insert_by_timestamp(history_version_path(), version)
  end

  @impl true
  def ghosted_versions do
    list(ghosted_version_path())
  end

  @impl true
  def add_ghosted_version(version_map) when is_map(version_map) do
    # Retrieve current ghosted version list
    current_list = ghosted_versions()

    ghosted_version? = Enum.any?(current_list, &(&1.version == version_map.version))

    # Add the version if not in the list
    if ghosted_version? == false do
      insert_by_timestamp(ghosted_version_path(), version_map)

      {:ok, [version_map | current_list]}
    else
      {:ok, current_list}
    end
  end

  @impl true
  def config do
    get_by_key(config_path(), @config_key_file)
  end

  @impl true
  def config_update(config) do
    insert_by_key(config_path(), @config_key_file, config)

    {:ok, config}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp service_path, do: "#{base_path()}/service/#{monitored_app()}"
  defp log_path, do: Application.fetch_env!(:deployex, :monitored_app_log_path)

  defp config_path,
    do: "#{base_path()}/storage/#{monitored_app()}/deployex/config"

  defp history_version_path,
    do: "#{base_path()}/storage/#{monitored_app()}/deployex/history"

  defp ghosted_version_path,
    do: "#{base_path()}/storage/#{monitored_app()}/deployex/ghosted"

  defp insert_by_timestamp(path, data) do
    file = "#{System.os_time(:microsecond)}.term"
    File.write!("#{path}/#{file}", :erlang.term_to_binary(data))
  end

  defp insert_by_key(path, key, data) do
    File.write!("#{path}/#{key}", :erlang.term_to_binary(data))
  end

  defp get_by_key(path, key) do
    case File.read("#{path}/" <> key) do
      {:ok, data} ->
        Plug.Crypto.non_executable_binary_to_term(data)

      {:error, _reason} ->
        nil
    end
  end

  defp list(path) do
    path
    |> File.ls!()
    |> Enum.map(fn file ->
      ("#{path}/" <> file)
      |> File.read!()
      |> Plug.Crypto.non_executable_binary_to_term()
    end)
  end
end
