defmodule Deployex.Storage.Local do
  @moduledoc """
  This module contains all paths for services and also initialize the directories
  """

  @behaviour Deployex.Storage.Adapter

  alias Deployex.Common

  @deployex_instance 0

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @impl true
  def init do
    create_storage_folder = fn instance ->
      File.mkdir_p!("#{base_path()}/storage/#{monitored_app()}/#{instance}")
    end

    replicas_list()
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
    version_list =
      history_version_path()
      |> read_data_from_file() || []

    Enum.map(version_list, fn version ->
      %{version | "inserted_at" => NaiveDateTime.from_iso8601!(version["inserted_at"])}
    end)
    |> Enum.sort_by(& &1["inserted_at"], {:desc, NaiveDateTime})
  end

  @impl true
  def versions(instance) do
    versions()
    |> Enum.filter(&(&1["instance"] == instance))
  end

  @impl true
  def add_version(version) do
    new_list = [version | versions()]

    json_list = Jason.encode!(new_list)

    history_version_path()
    |> File.write!(json_list)
  end

  @impl true
  def ghosted_versions do
    ghosted_version_path()
    |> read_data_from_file() || []
  end

  @impl true
  def add_ghosted_version(version_map) when is_map(version_map) do
    # Retrieve current ghosted version list
    current_list = ghosted_versions()

    ghosted_version? = Enum.any?(current_list, &(&1["version"] == version_map.version))

    # Add the version if not in the list
    if ghosted_version? == false do
      new_list = [version_map | current_list]

      json_list = Jason.encode!(new_list)

      ghosted_version_path()
      |> File.write!(json_list)

      {:ok, new_list}
    else
      {:ok, current_list}
    end
  end

  @impl true
  def config do
    deployex_config_path()
    |> read_data_from_file()
    |> Common.sanitize_schema_fields(%Deployex.Storage.Config{}, atoms: [:mode])
  end

  @impl true
  def config_update(config) do
    json_config = Jason.encode!(config)

    File.write!(deployex_config_path(), json_config)

    {:ok, config}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp service_path, do: "#{base_path()}/service/#{monitored_app()}"
  defp log_path, do: Application.fetch_env!(:deployex, :monitored_app_log_path)

  def deployex_config_path,
    do: "#{base_path()}/storage/#{monitored_app()}/#{@deployex_instance}/deployex.json"

  def history_version_path,
    do: "#{base_path()}/storage/#{monitored_app()}/#{@deployex_instance}/history.json"

  def ghosted_version_path,
    do: "#{base_path()}/storage/#{monitored_app()}/#{@deployex_instance}/ghosted.json"

  defp read_data_from_file(path) do
    file2json = fn data ->
      case Jason.decode(data) do
        {:ok, map} -> map
        _ -> nil
      end
    end

    case File.read(path) do
      {:ok, data} ->
        file2json.(data)

      _ ->
        nil
    end
  end
end
