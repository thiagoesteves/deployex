defmodule Deployex.Status.Application do
  @moduledoc """
  Module that host the current state and also provide functions to handle it
  """

  use GenServer
  alias Deployex.AppConfig
  alias Deployex.Common
  alias Deployex.Monitor

  @behaviour Deployex.Status.Adapter

  require Logger

  defstruct name: nil,
            instance: 0,
            version: nil,
            otp: nil,
            tls: :not_supported,
            last_deployment: nil,
            supervisor: false,
            status: nil,
            restarts: 0,
            uptime: nil,
            last_ghosted_version: nil

  @update_apps_interval :timer.seconds(1)
  @apps_data_updated_topic "monitoring_app_updated"

  ### ==========================================================================
  ### Callback GenServer functions
  ### ==========================================================================
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Process.flag(:trap_exit, true)

    :timer.send_interval(@update_apps_interval, :update_apps)

    {:ok, %{instances: AppConfig.replicas(), monitoring: []}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_info(:update_apps, %{monitoring: monitoring} = state) do
    deployex = update_deployex_app()

    monitoring_apps =
      AppConfig.replicas_list()
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
  ### Callback Deployex.Status.Adapter functions
  ### ==========================================================================

  @impl true
  def state do
    Common.call_gen_server(__MODULE__, :state)
  end

  @impl true
  def current_version(instance) do
    current_version_map(instance)["version"]
  end

  @impl true
  def current_version_map(instance) do
    instance
    |> AppConfig.current_version_path()
    |> read_data_from_file()
  end

  @impl true
  def listener_topic do
    @apps_data_updated_topic
  end

  @impl true
  def set_current_version_map(instance, release, attrs) do
    version =
      %{
        version: release["version"],
        hash: release["hash"],
        pre_commands: release["pre_commands"],
        instance: instance,
        deployment: Keyword.get(attrs, :deployment),
        deploy_ref: inspect(Keyword.get(attrs, :deploy_ref)),
        inserted_at: NaiveDateTime.utc_now()
      }

    write_current_version = fn version ->
      json_version = Jason.encode!(version)

      instance
      |> AppConfig.current_version_path()
      |> File.write!(json_version)
    end

    write_history_version = fn version ->
      new_list = [version | history_version_list()]

      json_list = Jason.encode!(new_list)

      AppConfig.history_version_path()
      |> File.write!(json_list)
    end

    with :ok <- write_current_version.(version) do
      write_history_version.(version)
    end
  end

  @impl true
  def add_ghosted_version(version) when is_map(version) do
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

  @impl true
  def ghosted_version_list do
    AppConfig.ghosted_version_path()
    |> read_data_from_file() || []
  end

  @impl true
  def history_version_list do
    version_list =
      AppConfig.history_version_path()
      |> read_data_from_file() || []

    Enum.map(version_list, fn version ->
      %{version | "inserted_at" => NaiveDateTime.from_iso8601!(version["inserted_at"])}
    end)
    |> Enum.sort_by(& &1["inserted_at"], {:desc, NaiveDateTime})
  end

  @impl true
  def history_version_list(instance) when is_binary(instance) do
    history_version_list(String.to_integer(instance))
  end

  @impl true
  def history_version_list(instance) when is_number(instance) do
    history_version_list()
    |> Enum.filter(&(&1["instance"] == instance))
  end

  @impl true
  def clear_new(instance) do
    instance
    |> AppConfig.new_path()
    |> File.rm_rf()

    instance
    |> AppConfig.new_path()
    |> File.mkdir_p()

    :ok
  end

  @impl true
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

    uptime = Common.uptime_to_string(Application.get_env(:deployex, :booted_at))

    last_ghosted_version =
      case ghosted_version_list() do
        [] -> "-/-"
        list -> Enum.at(list, 0)["version"]
      end

    %Deployex.Status{
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
    %{deployment_status: deployment_status, restarts: restarts, uptime: uptime} =
      check_monitor_data(instance)

    check_otp_monitored_app = fn
      instance, :running ->
        case Deployex.Upgrade.connect(instance) do
          {:ok, _} -> :connected
          _ -> :not_connected
        end

      _instance, _deployment ->
        :not_connected
    end

    %Deployex.Status{
      name: Application.get_env(:deployex, :monitored_app_name),
      instance: instance,
      version: current_version(instance),
      otp: check_otp_monitored_app.(instance, deployment_status),
      tls: check_tls(),
      last_deployment: current_version_map(instance)["deployment"],
      supervisor: false,
      status: deployment_status,
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
          deployment_status: state.status,
          restarts: state.restarts,
          uptime: Common.uptime_to_string(state.start_time)
        }

      _ ->
        %{deployment_status: nil, restarts: nil, uptime: Common.uptime_to_string(nil)}
    end
  end
end
