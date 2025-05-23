defmodule Deployer.Status.Application do
  @moduledoc """
  Module that host the current state and also provide functions to handle it
  """

  use GenServer
  require Logger

  @behaviour Deployer.Status.Adapter

  alias Deployer.Monitor
  alias Deployer.Status
  alias Foundation.Catalog
  alias Foundation.Common

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

    {:ok, %{monitoring: []}}
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

    sname_to_node = fn sname ->
      %{node: node} = Catalog.node_info(sname)
      node
    end

    monitoring_apps =
      Monitor.list()
      |> Enum.map(&sname_to_node.(&1))
      |> Enum.map(fn node ->
        update_monitored_app_name(node)
      end)

    new_monitoring = [deployex] ++ monitoring_apps

    Phoenix.PubSub.broadcast(
      Deployer.PubSub,
      @apps_data_updated_topic,
      {:monitoring_app_updated, Node.self(), new_monitoring}
    )

    {:noreply, %{state | monitoring: new_monitoring}}
  end

  ### ==========================================================================
  ### Callback Deployer.Status.Adapter functions
  ### ==========================================================================

  @impl true
  def monitoring(name \\ __MODULE__) do
    Common.call_gen_server(name, :monitoring)
  end

  @impl true
  def monitored_app_name, do: Catalog.monitored_app_name()

  @impl true
  def monitored_app_lang, do: Catalog.monitored_app_lang()

  @impl true
  def subscribe, do: Phoenix.PubSub.subscribe(Deployer.PubSub, @apps_data_updated_topic)

  @impl true
  def current_version(sname) do
    current_version_map(sname).version
  end

  @impl true
  def current_version_map(sname) do
    sname
    |> Catalog.versions()
    |> Enum.at(0)
    |> case do
      nil ->
        %Catalog.Version{}

      version ->
        version
    end
  end

  @impl true
  def set_current_version_map(sname, release, attrs) do
    %{name: name} = Catalog.node_info(sname)

    params = %Catalog.Version{
      version: release.version,
      hash: release.hash,
      pre_commands: release.pre_commands,
      sname: sname,
      name: name,
      deployment: Keyword.get(attrs, :deployment),
      inserted_at: NaiveDateTime.utc_now()
    }

    Catalog.add_version(params)
  end

  @impl true
  def add_ghosted_version(version), do: Catalog.add_ghosted_version(version)

  @impl true
  def ghosted_version_list do
    Catalog.ghosted_versions()
  end

  @impl true
  def history_version_list do
    Catalog.versions()
  end

  @impl true
  def history_version_list(sname) do
    Catalog.versions(sname)
  end

  @impl true
  def list_installed_apps(name) do
    case File.ls("#{Catalog.service_path(name)}") do
      {:ok, list} ->
        list

      _ ->
        []
    end
  end

  @impl true
  def update(nil), do: :ok

  def update(sname) do
    # Remove previous path
    sname
    |> Catalog.previous_path()
    |> File.rm_rf()

    # Move current to previous and new to current
    File.rename(Catalog.current_path(sname), Catalog.previous_path(sname))
    File.rename(Catalog.new_path(sname), Catalog.current_path(sname))
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
    config = Catalog.config()
    Catalog.config_update(%{config | mode: mode})
  end

  defp do_set_mode(:manual = mode, version) do
    versions = history_version_list()

    %Catalog.Config{
      mode: mode,
      manual_version: Enum.find(versions, &(&1.version == version))
    }
    |> Catalog.config_update()
  end

  defp update_deployex_app do
    check_otp_deployex = fn ->
      if Node.list() != [], do: :connected, else: :not_connected
    end

    uptime = Common.uptime_to_string(Application.get_env(:foundation, :booted_at))

    last_ghosted_version =
      case ghosted_version_list() do
        [] -> "-/-"
        list -> Enum.at(list, 0).version
      end

    config = Catalog.config()

    %Status{
      name: "deployex",
      sname: "deployex",
      version: Application.spec(:deployer, :vsn) |> to_string,
      otp: check_otp_deployex.(),
      tls: Common.check_mtls(),
      supervisor: true,
      status: :running,
      uptime: uptime,
      last_ghosted_version: last_ghosted_version,
      mode: config.mode,
      manual_version: config.manual_version
    }
  end

  defp update_monitored_app_name(node) do
    %{name: name, sname: sname} = Catalog.node_info(node)

    %{
      status: status,
      crash_restart_count: crash_restart_count,
      force_restart_count: force_restart_count,
      start_time: start_time
    } = Monitor.state(sname)

    check_otp_monitored_app = fn
      node, :running ->
        case Deployer.Upgrade.connect(node) do
          {:ok, _} -> :connected
          _ -> :not_connected
        end

      _node, _deployment ->
        :not_connected
    end

    %Status{
      name: name,
      sname: sname,
      node: node,
      version: current_version(sname),
      otp: check_otp_monitored_app.(node, status),
      tls: Common.check_mtls(),
      last_deployment: current_version_map(sname).deployment,
      supervisor: false,
      status: status,
      crash_restart_count: crash_restart_count,
      force_restart_count: force_restart_count,
      uptime: Common.uptime_to_string(start_time),
      language: Application.get_env(:foundation, :monitored_app_lang)
    }
  end
end
