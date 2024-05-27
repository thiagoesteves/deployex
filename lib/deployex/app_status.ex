defmodule Deployex.AppStatus do
  @moduledoc """
  Module that host the current state and also provide functions to handle it
  """

  use GenServer
  alias Deployex.Configuration
  alias Deployex.Storage

  require Logger

  defstruct name: nil,
            version: nil,
            otp: nil,
            tls: :not_supported,
            last_deployment: nil,
            prev_version: nil,
            supervisor: false,
            status: nil

  @update_apps_interval_ms 1_000
  @update_otp_distribution_interval_ms 5_000
  @apps_data_updated_topic "apps_data_updated"

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
    # update apps
    new_monitoring =
      [update_deployex_app()] ++
        Enum.map(1..instances, fn instance ->
          update_monitored_app(instance)
        end)

    if new_monitoring != monitoring do
      Phoenix.PubSub.broadcast(
        Deployex.PubSub,
        "apps_data_updated",
        {:update_apps_data, new_monitoring}
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
        IO.puts("here")

        instance
        |> previous_version_path()
        |> File.write!(version |> Jason.encode!())
    end

    version =
      version
      |> Map.put(:deployment, deployment)
      |> Jason.encode!()

    IO.puts("save")

    instance
    |> current_version_path()
    |> File.write!(version)
  end

  @spec clear_new(integer()) :: :ok
  def clear_new(instance) do
    instance
    |> Configuration.new_path()
    |> File.rm_rf()

    instance
    |> Configuration.new_path()
    |> File.mkdir_p()

    :ok
  end

  @spec update(integer()) :: :ok
  def update(instance) do
    # Remove previous path
    instance
    |> Configuration.previous_path()
    |> File.rm_rf()

    # Move current to previous and new to current
    File.rename(Configuration.current_path(instance), Configuration.previous_path(instance))
    File.rename(Configuration.new_path(instance), Configuration.current_path(instance))
    :ok
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp current_version_path(instance),
    do: "#{Configuration.base_path()}/version/#{instance}/current.json"

  defp previous_version_path(instance),
    do: "#{Configuration.base_path()}/version/#{instance}/previous.json"

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
      version: Application.spec(:deployex, :vsn) |> to_string,
      last_deployment: nil,
      otp: check_otp(),
      tls: check_tls(),
      prev_version: nil,
      supervisor: true,
      status: :running
    }
  end

  defp update_monitored_app(instance) do
    %Deployex.AppStatus{
      name: Application.get_env(:deployex, :monitored_app_name),
      version: current_version(instance),
      otp: check_otp(),
      tls: check_tls(),
      last_deployment: current_deployment(instance),
      prev_version: prev_version(instance),
      supervisor: false,
      status: check_deployment(instance)
    }
  end

  defp check_otp do
    if Node.list() != [], do: :connected, else: :not_connected
  end

  defp check_tls do
    if :init.get_arguments()[:ssl_dist_optfile] do
      :supported
    else
      :not_supported
    end
  end

  defp check_deployment(instance) do
    storage = Storage.get_current_version_map()

    if storage["version"] == current_version(instance) do
      :running
    else
      :deploying
    end
  end
end
