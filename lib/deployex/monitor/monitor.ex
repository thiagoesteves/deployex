defmodule Deployex.Monitor do
  @moduledoc """
  GenServer that monitor and supervise the application.
  """
  use GenServer
  require Logger

  alias Deployex.{AppStatus, Configuration, Deployment}

  defstruct current_pid: nil,
            instance: 0,
            status: :idle,
            restarts: 0,
            start_time: nil

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: global_name(args))
  end

  @impl true
  def init(instance: instance) do
    Process.flag(:trap_exit, true)

    Logger.info("Initialising monitor server for instance: #{instance}")

    Logger.metadata(instance: instance)

    current_version = AppStatus.current_version(instance)

    state =
      %__MODULE__{instance: instance}
      |> run_service(current_version)

    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:start_service, _from, %{instance: instance, current_pid: current_pid})
      when is_nil(current_pid) do
    current_version = AppStatus.current_version(instance)

    state = run_service(%__MODULE__{instance: instance}, current_version)

    {:reply, :ok, state}
  end

  def handle_call(:start_service, _from, %__MODULE__{current_pid: current_pid} = state) do
    {:reply, {:error, current_pid, :already_started}, state}
  end

  def handle_call(
        :stop_service,
        _from,
        %__MODULE__{current_pid: current_pid, instance: instance} = state
      )
      when is_nil(current_pid) do
    Logger.info("Requested instance: #{instance} to stop but application is not running.")
    {:reply, :ok, state}
  end

  def handle_call(:stop_service, _from, %__MODULE__{current_pid: current_pid} = state)
      when is_nil(current_pid) do
    {:reply, :ok, state}
  end

  def handle_call(
        :stop_service,
        _from,
        %__MODULE__{current_pid: current_pid, instance: instance} = state
      ) do
    Logger.info(
      "Requested instance: #{instance} to stop application pid: #{inspect(current_pid)}"
    )

    # Stop current application
    :exec.stop(current_pid)

    # NOTE: The next command is needed for Systems that have a different PID for the "/bin/app start" script
    #       and the bin/beam.smp process
    :exec.run(
      "kill -9 $(ps -ax | grep \"#{Configuration.monitored_app()}/#{instance}/current/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
      [:sync, :stdout, :stderr]
    )

    {:reply, :ok, reset_state(state)}
  end

  @impl true
  def handle_info(
        {:check_running, pid},
        %__MODULE__{current_pid: current_pid, instance: instance} = state
      )
      when pid == current_pid do
    Logger.info("Application instance: #{instance} is running")
    Deployment.notify_application_running(instance)
    {:noreply, %{state | status: :running}}
  end

  def handle_info({:check_running, _pid}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:EXIT, pid, reason},
        %__MODULE__{current_pid: current_pid, instance: instance, restarts: restarts} = state
      ) do
    state =
      if current_pid == pid do
        Logger.error(
          "Unexpected exit message received for instance: #{instance} from pid: #{inspect(pid)} being restarted"
        )

        current_version = AppStatus.current_version(instance)

        run_service(%{state | restarts: restarts + 1}, current_version)
      else
        Logger.warning(
          "Application instance: #{instance} with pid: #{inspect(pid)} being stopped by reason: #{inspect(reason)}"
        )

        state
      end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @spec start_service(integer()) ::
          :ok | {:error, pid(), :already_started} | {:error, :rescued}
  def start_service(instance) do
    call_gen_server(instance, :start_service)
  end

  @spec stop_service(integer()) :: :ok | {:error, :rescued}
  def stop_service(instance) do
    call_gen_server(instance, :stop_service)
  end

  @spec state(integer()) :: {:ok, %__MODULE__{}} | {:error, :rescued}
  def state(instance) do
    call_gen_server(instance, :state)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp global_name(instance: instance), do: {:global, %{instance: instance}}
  defp global_name(instance), do: {:global, %{instance: instance}}

  # NOTE: This function needs to use try/catch because reascue (suggested by credo)
  #       doesn't handle :exit
  defp call_gen_server(instance, message) do
    try do
      GenServer.call(global_name(instance), message)
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  defp run_service(state, nil) do
    Logger.info("No version set, not able to run_service")
    state
  end

  defp run_service(%__MODULE__{instance: instance} = state, version) do
    Logger.info("Ensure running requested for instance: #{instance} version: #{version}")

    executable = executable_path(instance)

    state =
      if File.exists?(executable) do
        Logger.info(" - Starting #{executable}...")

        {:ok, pid, os_pid} =
          :exec.run_link(pre_commands(instance) <> executable <> " start", [
            {:stdout, Configuration.stdout_path(instance)},
            {:stderr, Configuration.stderr_path(instance)}
          ])

        Logger.info(
          " - Running instance: #{instance}, monitoring pid = #{inspect(pid)}, OS process id = #{os_pid}."
        )

        %{state | current_pid: pid, status: :starting, start_time: now()}
      else
        Logger.error("Version set but no #{executable}")

        reset_state(state)
      end

    if state.current_pid do
      Process.send_after(self(), {:check_running, state.current_pid}, 3_000)
    end

    state
  end

  # NOTE: These are commands that need to run prior starting the application
  #       - Unset env vars from the deployex release to not mix with the monitored app release
  #       - Export suffix to add different snames to the apps
  #       - Export phoenix listening port taht needs to be one per app
  defp pre_commands(instance) do
    phx_port = Configuration.phx_start_port() + (instance - 1)

    """
    unset $(env | grep RELEASE | awk -F'=' '{print $1}')
    export RELEASE_NODE_SUFFIX=-#{instance}
    export PORT=#{phx_port}
    """
  end

  defp executable_path(instance) do
    Path.join([Configuration.current_path(instance), "bin", Configuration.monitored_app()])
  end

  defp now, do: System.os_time(:second)

  defp reset_state(state),
    do: %{state | status: :idle, current_pid: nil, restarts: 0, start_time: nil}
end
