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
  def handle_call(:monitoring, _from, state) do
    {:reply, {:ok, state.monitoring}, state}
  end

  def handle_call({:set_mode, mode, version}, _from, state) do
    res = do_set_mode(mode, version)
    {:reply, res, state}
  end

  @impl true
  def handle_info(:update_apps, state) do
    deployex = update_deployex_app()

    monitoring_apps =
      Storage.replicas_list()
      |> Enum.map(fn instance ->
        update_monitored_app(instance)
      end)

    new_monitoring = [deployex] ++ monitoring_apps

    Phoenix.PubSub.broadcast(
      Deployex.PubSub,
      @apps_data_updated_topic,
      {:monitoring_app_updated, Node.self(), new_monitoring}
    )

    {:noreply, %{state | monitoring: new_monitoring}}
  end

  ### ==========================================================================
  ### Callback Deployex.Status.Adapter functions
  ### ==========================================================================

  @impl true
  def monitoring(name \\ __MODULE__) do
    Common.call_gen_server(name, :monitoring)
  end

  @impl true
  def subscribe, do: Phoenix.PubSub.subscribe(Deployex.PubSub, @apps_data_updated_topic)

  @impl true
  def current_version(instance) do
    current_version_map(instance).version
  end

  @impl true
  def current_version_map(instance) do
    instance
    |> Storage.versions()
    |> Enum.at(0)
    |> case do
      nil ->
        %Deployex.Status.Version{}

      version ->
        version
    end
  end

  @impl true
  def set_current_version_map(instance, release, attrs) do
    params = %Deployex.Status.Version{
      version: release.version,
      hash: release.hash,
      pre_commands: release.pre_commands,
      instance: instance,
      deployment: Keyword.get(attrs, :deployment),
      deploy_ref: Keyword.get(attrs, :deploy_ref),
      inserted_at: NaiveDateTime.utc_now()
    }

    Storage.add_version(params)
  end

  @impl true
  def add_ghosted_version(version), do: Storage.add_ghosted_version(version)

  @impl true
  def ghosted_version_list do
    Storage.ghosted_versions()
  end

  @impl true
  def history_version_list do
    Storage.versions()
  end

  @impl true
  def history_version_list(instance) when is_binary(instance) do
    history_version_list(String.to_integer(instance))
  end

  @impl true
  def history_version_list(instance) do
    Storage.versions(instance)
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

  @impl true
  def set_mode(module \\ __MODULE__, mode, version) when mode in [:manual, :automatic] do
    Common.call_gen_server(module, {:set_mode, mode, version})
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp do_set_mode(:automatic = mode, _version) do
    config = Storage.config()
    Storage.config_update(%{config | mode: mode})
  end

  defp do_set_mode(:manual = mode, version) do
    versions = history_version_list()

    %Deployex.Storage.Config{
      mode: mode,
      manual_version: Enum.find(versions, &(&1.version == version))
    }
    |> Storage.config_update()
  end

  defp update_deployex_app do
    check_otp_deployex = fn ->
      if Node.list() != [], do: :connected, else: :not_connected
    end

    uptime = Common.uptime_to_string(Application.get_env(:deployex, :booted_at))

    last_ghosted_version =
      case ghosted_version_list() do
        [] -> "-/-"
        list -> Enum.at(list, 0).version
      end

    config = Storage.config()

    %Deployex.Status{
      name: "deployex",
      version: Application.spec(:deployex, :vsn) |> to_string,
      otp: check_otp_deployex.(),
      tls: check_tls(),
      supervisor: true,
      status: :running,
      uptime: uptime,
      last_ghosted_version: last_ghosted_version,
      mode: config.mode,
      manual_version: config.manual_version
    }
  end

  defp update_monitored_app(instance) do
    %{
      status: status,
      crash_restart_count: crash_restart_count,
      force_restart_count: force_restart_count,
      start_time: start_time
    } = Monitor.state(instance)

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
      last_deployment: current_version_map(instance).deployment,
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
end
