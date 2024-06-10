defmodule Deployex.AppStatus do
  @moduledoc """
  Module that host the current state and also provide functions to handle it
  """

  use GenServer
  alias Deployex.AppConfig
  alias Deployex.Monitor
  alias Deployex.Storage

  require Logger

  defstruct name: nil,
            instance: 0,
            version: nil,
            otp: nil,
            tls: :not_supported,
            last_deployment: nil,
            prev_version: nil,
            supervisor: false,
            status: nil,
            restarts: 0,
            uptime: nil

  @update_apps_interval_ms 1_000
  @update_otp_distribution_interval_ms 5_000
  @apps_data_updated_topic "monitoring_app_updated"

  @sec_in_minute 60
  @sec_in_hour 3_600
  @sec_in_day 86_400
  @sec_in_months 2_628_000

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(instances: instances) do
    Process.flag(:trap_exit, true)

    :timer.send_interval(@update_apps_interval_ms, :update_apps)
    :timer.send_interval(@update_otp_distribution_interval_ms, :update_otp)

    {:ok, %{instances: instances, monitoring: []}}
  end

  @impl true
  def handle_info(:update_apps, %{instances: instances, monitoring: monitoring} = state) do
    deployex = update_deployex_app()

    monitoring_apps =
      Enum.to_list(1..instances)
      |> Enum.map(fn instance ->
        update_monitored_app(instance)
      end)

    new_monitoring = [deployex] ++ monitoring_apps

    if new_monitoring != monitoring do
      Phoenix.PubSub.broadcast(
        Deployex.PubSub,
        @apps_data_updated_topic,
        {:monitoring_app_updated, new_monitoring}
      )
    end

    {:noreply, %{state | monitoring: new_monitoring}}
  end

  @impl true
  def handle_info(:update_otp, state) do
    # Check if there is any version expected to be deployed
    expected_current_version = Storage.get_current_version_map()["version"]

    # Check if the nodes are connected
    if expected_current_version != nil and Node.list() == [], do: Deployex.Upgrade.connect(1)
    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @spec current_version(integer()) :: String.t() | nil
  def current_version(instance) do
    current_version_map(instance)["version"]
  end

  @spec current_deployment(integer()) :: String.t() | nil
  def current_deployment(instance) do
    current_version_map(instance)["deployment"]
  end

  @spec listener_topic() :: String.t()
  def listener_topic do
    @apps_data_updated_topic
  end

  @spec set_current_version_map(integer(), Deployex.Storage.version_map(), atom()) :: :ok
  def set_current_version_map(instance, version, deployment) when is_map(version) do
    # Update previous version
    case current_version_map(instance) do
      nil ->
        Logger.warning("No previous version set")

      version ->
        instance
        |> previous_version_path()
        |> File.write!(version |> Jason.encode!())
    end

    version =
      version
      |> Map.put(:deployment, deployment)
      |> Jason.encode!()

    instance
    |> current_version_path()
    |> File.write!(version)
  end

  @spec clear_new(integer()) :: :ok
  def clear_new(instance) do
    instance
    |> AppConfig.new_path()
    |> File.rm_rf()

    instance
    |> AppConfig.new_path()
    |> File.mkdir_p()

    :ok
  end

  @spec update(integer()) :: :ok
  def update(instance) do
    # Remove previous path
    instance
    |> AppConfig.previous_path()
    |> File.rm_rf()

    # Move current to previous and new to current
    File.rename(AppConfig.current_path(instance), AppConfig.previous_path(instance))
    File.rename(AppConfig.new_path(instance), AppConfig.current_path(instance))
    :ok
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp current_version_path(instance),
    do: "#{AppConfig.base_path()}/version/#{instance}/current.json"

  defp previous_version_path(instance),
    do: "#{AppConfig.base_path()}/version/#{instance}/previous.json"

  defp current_version_map(instance) do
    instance
    |> current_version_path()
    |> version_map()
  end

  defp previous_version_map(instance) do
    instance
    |> previous_version_path()
    |> version_map()
  end

  defp version_map(path) do
    case File.read(path) do
      {:ok, data} ->
        file2json(data)

      _ ->
        nil
    end
  end

  defp file2json(data) do
    case Jason.decode(data) do
      {:ok, map} -> map
      _ -> nil
    end
  end

  defp prev_version(instance) do
    previous_version_map(instance)["version"]
  end

  defp update_deployex_app do
    %Deployex.AppStatus{
      name: "deployex",
      instance: 0,
      version: Application.spec(:deployex, :vsn) |> to_string,
      last_deployment: nil,
      otp: check_deployex(),
      tls: check_tls(),
      prev_version: nil,
      supervisor: true,
      status: :running,
      uptime: "-/-"
    }
  end

  defp update_monitored_app(instance) do
    %{deployment: deployment, restarts: restarts, uptime: uptime} = check_monitor_data(instance)

    %Deployex.AppStatus{
      name: Application.get_env(:deployex, :monitored_app_name),
      instance: instance,
      version: current_version(instance),
      otp: check_otp(instance),
      tls: check_tls(),
      last_deployment: current_deployment(instance),
      prev_version: prev_version(instance),
      supervisor: false,
      status: deployment,
      restarts: restarts,
      uptime: uptime
    }
  end

  defp check_deployex do
    if Node.list() != [], do: :connected, else: :not_connected
  end

  defp check_otp(instance) do
    case Deployex.Upgrade.connect(instance) do
      {:ok, _} -> :connected
      _ -> :not_connected
    end
  end

  defp check_tls do
    if :init.get_arguments()[:ssl_dist_optfile] do
      :supported
    else
      :not_supported
    end
  end

  defp check_monitor_data(instance) do
    case Monitor.state(instance) do
      {:ok, state} ->
        %{
          deployment: state.status,
          restarts: state.restarts,
          uptime: uptime_to_string(state.start_time)
        }

      _ ->
        %{deployment: nil, restarts: nil, uptime: "/"}
    end
  end

  defp now, do: System.os_time(:second)

  defp uptime_to_string(nil), do: "-/-"

  defp uptime_to_string(start_time) do
    diff = now() - start_time

    case diff do
      uptime when uptime < 10 -> "now"
      uptime when uptime < @sec_in_minute -> "<1m"
      uptime when uptime < @sec_in_hour -> "#{trunc(uptime / @sec_in_minute)}m"
      uptime when uptime < @sec_in_day -> "#{trunc(uptime / @sec_in_hour)}h"
      uptime when uptime <= @sec_in_months -> "#{trunc(uptime / @sec_in_day)}d"
      uptime -> "#{trunc(uptime / @sec_in_months)}d"
    end
  end
end
