defmodule Deployex.Status.Application do
  @moduledoc """
  Module that host the current state and also provide functions to handle it
  """

  use GenServer
  alias Deployex.Common
  alias Deployex.Monitor
  alias Deployex.Storage

  @behaviour Deployex.Status.Adapter

  require Logger

  @update_apps_interval :timer.seconds(1)
  @apps_data_updated_topic "monitoring_app_updated"

  ### ==========================================================================
  ### Callback GenServer functions
  ### ==========================================================================
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)

    args
    |> Keyword.get(:update_apps_interval, @update_apps_interval)
    |> :timer.send_interval(:update_apps)

    {:ok, %{instances: Storage.replicas(), monitoring: []}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_info(:update_apps, %{monitoring: monitoring} = state) do
    deployex = update_deployex_app()

    monitoring_apps =
      Storage.replicas_list()
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
  def state(name \\ __MODULE__) do
    Common.call_gen_server(name, :state)
  end

  @impl true
  def listener_topic, do: @apps_data_updated_topic

  @impl true
  def current_version(instance) do
    Storage.current_version_map(instance)["version"]
  end

  @impl true
  def current_version_map(instance), do: Storage.current_version_map(instance)

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

    with :ok <- Storage.set_current_version_map(instance, version) do
      Storage.add_version(version)
    end
  end

  @impl true
  def add_ghosted_version(version), do: Storage.add_ghosted_version_map(version)

  @impl true
  def ghosted_version_list, do: Storage.ghosted_versions()

  @impl true
  def history_version_list, do: Storage.versions()

  @impl true
  def history_version_list(instance) when is_binary(instance) do
    history_version_list(String.to_integer(instance))
  end

  @impl true
  def history_version_list(instance) when is_number(instance) do
    Storage.versions()
    |> Enum.filter(&(&1["instance"] == instance))
  end

  @impl true
  def clear_new(instance) do
    instance
    |> Storage.new_path()
    |> File.rm_rf()

    instance
    |> Storage.new_path()
    |> File.mkdir_p()

    :ok
  end

  @impl true
  def update(instance) do
    # Remove previous path
    instance
    |> Storage.previous_path()
    |> File.rm_rf()

    # Move current to previous and new to current
    File.rename(Storage.current_path(instance), Storage.previous_path(instance))
    File.rename(Storage.new_path(instance), Storage.current_path(instance))
    :ok
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
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
    %{
      status: status,
      crash_restart_count: crash_restart_count,
      force_restart_count: force_restart_count,
      start_time: start_time
    } = check_monitor_data(instance)

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
      otp: check_otp_monitored_app.(instance, status),
      tls: check_tls(),
      last_deployment: current_version_map(instance)["deployment"],
      supervisor: false,
      status: status,
      crash_restart_count: crash_restart_count,
      force_restart_count: force_restart_count,
      uptime: Common.uptime_to_string(start_time)
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
        state

      _ ->
        %Deployex.Monitor{}
    end
  end
end
