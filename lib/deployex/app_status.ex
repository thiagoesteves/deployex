defmodule Deployex.AppStatus do
  @moduledoc """
  Module that host the current state and also provide functions to handle it
  """

  use GenServer
  alias Deployex.Configuration
  alias Deployex.Storage

  require Logger

  defstruct [
    :name,
    :link,
    :version,
    :otp,
    :tls,
    :last_deployment,
    :prev_version,
    :supervisor,
    :status
  ]

  @update_interval_ms 1_000
  @apps_data_updated_topic "apps_data_updated"

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(attrs) do
    GenServer.start_link(__MODULE__, attrs, name: __MODULE__)
  end

  @impl true
  def init(_attrs) do
    Process.flag(:trap_exit, true)

    :timer.send_interval(@update_interval_ms, :update_apps)

    {:ok, []}
  end

  @impl true
  def handle_info(:update_apps, state) do
    new_state = [
      update_deployex_app(),
      update_monitored_app()
    ]

    if new_state != state do
      Phoenix.PubSub.broadcast(
        Deployex.PubSub,
        "apps_data_updated",
        {:update_apps_data, new_state}
      )
    end

    {:noreply, new_state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @spec current_version() :: String.t() | nil
  def current_version do
    version_map()["version"]
  end

  @spec current_deployment() :: String.t() | nil
  def current_deployment do
    version_map()["deployment"]
  end

  @spec listener_topic() :: String.t()
  def listener_topic do
    @apps_data_updated_topic
  end

  @spec set_current_version_map(Deployex.Storage.version_map(), atom()) :: :ok
  def set_current_version_map(version, deployment) when is_map(version) do
    # Update previous version
    case version_map() do
      nil ->
        Logger.warning("No previous version set")

      version ->
        File.write!(previous_version_path(), version |> Jason.encode!())
    end

    version =
      version
      |> Map.put(:deployment, deployment)
      |> Jason.encode!()

    File.write!(current_version_path(), version)
  end

  @spec clear_new() :: :ok
  def clear_new do
    File.rm_rf(Configuration.new_path())
    File.mkdir_p(Configuration.new_path())
    :ok
  end

  @spec update() :: :ok
  def update do
    File.rm_rf(Configuration.old_path())
    File.rename(Configuration.current_path(), Configuration.old_path())
    File.rename(Configuration.new_path(), Configuration.current_path())
    :ok
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp current_version_path, do: "#{Configuration.base_path()}/current.json"
  defp previous_version_path, do: "#{Configuration.base_path()}/previous.json"

  defp version_map(path \\ current_version_path()) do
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

  defp prev_version do
    previous_version_path()
    |> version_map()
    |> Map.get("version")
  end

  defp update_deployex_app do
    %Deployex.AppStatus{
      name: "deployex",
      link: true,
      version: Application.spec(:deployex, :vsn) |> to_string,
      last_deployment: nil,
      otp: check_otp(),
      tls: check_tls(),
      prev_version: nil,
      supervisor: true,
      status: :running
    }
  end

  defp update_monitored_app do
    %Deployex.AppStatus{
      name: Application.get_env(:deployex, :monitored_app_name),
      link: false,
      version: current_version(),
      otp: check_otp(),
      tls: check_tls(),
      last_deployment: current_deployment(),
      prev_version: prev_version(),
      supervisor: false,
      status: check_deployment()
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

  defp check_deployment do
    storage = Storage.get_current_version_map()

    if storage["version"] == current_version() do
      :running
    else
      :deploying
    end
  end
end
