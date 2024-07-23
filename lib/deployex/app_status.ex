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
            previous_version: nil,
            supervisor: false,
            status: nil,
            restarts: 0,
            uptime: nil,
            last_ghosted_version: nil

  @update_apps_interval :timer.seconds(1)
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

    :timer.send_interval(@update_apps_interval, :update_apps)

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

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @spec current_version(integer()) :: String.t() | nil
  def current_version(instance) do
    current_version_map(instance)["version"]
  end

  @spec current_version_map(integer()) :: Storage.version_map() | nil
  def current_version_map(instance) do
    instance
    |> AppConfig.current_version_path()
    |> read_data_from_file()
  end

  @spec previous_version_map(integer()) :: Storage.version_map() | nil
  def previous_version_map(instance) do
    instance
    |> AppConfig.previous_version_path()
    |> read_data_from_file()
  end

  @spec listener_topic() :: String.t()
  def listener_topic do
    @apps_data_updated_topic
  end

  @spec set_current_version_map(integer(), Storage.version_map(), Keyword.t()) :: :ok
  def set_current_version_map(instance, version, attrs) when is_map(version) do
    # Update previous version
    case current_version_map(instance) do
      nil ->
        Logger.warning("No previous version set")

      current_version ->
        instance
        |> AppConfig.previous_version_path()
        |> File.write!(current_version |> Jason.encode!())
    end

    version =
      version
      |> Map.put(:deployment, Keyword.get(attrs, :deployment))
      |> Map.put(:deploy_ref, inspect(Keyword.get(attrs, :deploy_ref)))
      |> Jason.encode!()

    instance
    |> AppConfig.current_version_path()
    |> File.write!(version)
  end

  @spec add_ghosted_version_list(Storage.version_map()) :: {:ok, list()}
  def add_ghosted_version_list(version) when is_map(version) do
    # Retrieve current ghosted version list
    current_list = ghosted_version_list()

    ghosted_version? = Enum.any?(current_list, &(&1["version"] == version["version"]))

    # Add the version if not in the list
    if ghosted_version? == false do
      new_list = [version | current_list]

      json_list = Jason.encode!(new_list)

      AppConfig.ghosted_version_path()
      |> File.write!(json_list)

      {:ok, new_list}
    else
      {:ok, current_list}
    end
  end

  @spec ghosted_version_list :: list()
  def ghosted_version_list do
    AppConfig.ghosted_version_path()
    |> read_data_from_file() || []
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

  defp update_deployex_app do
    check_otp_deployex = fn ->
      if Node.list() != [], do: :connected, else: :not_connected
    end

    uptime = uptime_to_string(Application.get_env(:deployex, :booted_at))

    last_ghosted_version =
      case ghosted_version_list() do
        [] -> "-/-"
        list -> Enum.at(list, 0)["version"]
      end

    %Deployex.AppStatus{
      name: "deployex",
      version: Application.spec(:deployex, :vsn) |> to_string,
      otp: check_otp_deployex.(),
      tls: check_tls(),
      supervisor: true,
      status: :running,
      uptime: uptime,
      last_ghosted_version: last_ghosted_version
    }
  end

  defp update_monitored_app(instance) do
    %{deployment: deployment, restarts: restarts, uptime: uptime} = check_monitor_data(instance)

    check_otp_monitored_app = fn
      instance, :running ->
        case Deployex.Upgrade.connect(instance) do
          {:ok, _} -> :connected
          _ -> :not_connected
        end

      _instance, _deployment ->
        :not_connected
    end

    %Deployex.AppStatus{
      name: Application.get_env(:deployex, :monitored_app_name),
      instance: instance,
      version: current_version(instance),
      otp: check_otp_monitored_app.(instance, deployment),
      tls: check_tls(),
      last_deployment: current_version_map(instance)["deployment"],
      previous_version: previous_version_map(instance)["version"],
      supervisor: false,
      status: deployment,
      restarts: restarts,
      uptime: uptime
    }
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

  defp uptime_to_string(nil), do: "-/-"

  defp uptime_to_string(start_time) do
    diff = System.convert_time_unit(System.monotonic_time() - start_time, :native, :second)

    case diff do
      uptime when uptime < 10 -> "now"
      uptime when uptime < @sec_in_minute -> "<1m ago"
      uptime when uptime < @sec_in_hour -> "#{trunc(uptime / @sec_in_minute)}m ago"
      uptime when uptime < @sec_in_day -> "#{trunc(uptime / @sec_in_hour)}h ago"
      uptime when uptime <= @sec_in_months -> "#{trunc(uptime / @sec_in_day)}d ago"
      uptime -> "#{trunc(uptime / @sec_in_months)}d ago"
    end
  end
end
