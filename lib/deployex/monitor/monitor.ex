defmodule Deployex.Monitor do
  @moduledoc """
  GenServer that monitor and supervise the application.
  """
  use GenServer
  require Logger

  alias Deployex.{AppConfig, AppStatus, Common, Deployment}

  defstruct current_pid: nil,
            instance: 0,
            status: :idle,
            restarts: 0,
            start_time: nil,
            deploy_ref: :init

  # NOTE: Timeout to check if the application crashed for any reason
  @timeout_to_verify_app_ready :timer.seconds(30)

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

    {:ok, %__MODULE__{instance: instance}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(
        {:start_service, deploy_ref},
        _from,
        %__MODULE__{current_pid: current_pid} = state
      )
      when is_nil(current_pid) do
    trigger_run_service(deploy_ref)

    {:reply, :ok, reset_state(state, deploy_ref)}
  end

  def handle_call(:stop_service, _from, %__MODULE__{current_pid: current_pid} = state)
      when is_nil(current_pid) do
    Logger.warning(
      "Requested instance: #{state.instance} to stop but application is not running."
    )

    {:reply, :ok, state}
  end

  def handle_call(:stop_service, _from, state) do
    Logger.info(
      "Requested instance: #{state.instance} to stop application pid: #{inspect(state.current_pid)}"
    )

    # Stop current application
    :exec.stop(state.current_pid)

    # NOTE: The next command is needed for Systems that have a different PID for the "/bin/app start" script
    #       and the bin/beam.smp process
    cleanup_beam_process(state.instance)

    {:reply, :ok, reset_state(state)}
  end

  @impl true
  def handle_info({:run_service, deploy_ref}, state) when deploy_ref == state.deploy_ref do
    version_map = AppStatus.current_version_map(state.instance)

    state =
      if version_map == nil do
        Logger.info("No version set, not able to run_service")
        state
      else
        Logger.info(
          "Ensure running requested for instance: #{state.instance} version: #{version_map["version"]}"
        )

        run_service(state, version_map)
      end

    {:noreply, state}
  end

  def handle_info({:run_service, _deploy_ref}, state) do
    # Do nothing, a different deployment was requested
    {:noreply, state}
  end

  def handle_info({:check_running, pid, deploy_ref}, state)
      when pid == state.current_pid and deploy_ref == state.deploy_ref do
    Logger.info(" # Application instance: #{state.instance} is running")

    Deployment.notify_application_running(state.instance, deploy_ref)

    {:noreply, %{state | status: :running}}
  end

  def handle_info({:check_running, _pid, _deploy_ref}, state) do
    {:noreply, state}
  end

  def handle_info({:EXIT, pid, _reason}, %{current_pid: current_pid} = state)
      when current_pid == pid do
    Logger.error(
      "Unexpected exit message received for instance: #{state.instance} from pid: #{inspect(pid)}, application being restarted"
    )

    cleanup_beam_process(state.instance)

    # Update the number of restarts
    restarts = state.restarts + 1

    # Retry with backoff pattern
    trigger_run_service(state.deploy_ref, 2 * restarts * 1000)

    {:noreply, %{state | restarts: restarts}}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning(
      "Application instance: #{state.instance} with pid: #{inspect(pid)} being stopped by reason: #{inspect(reason)}"
    )

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @spec start_service(integer(), reference()) ::
          :ok | {:error, pid(), :already_started} | {:error, :rescued}
  def start_service(instance, deploy_ref) do
    call_gen_server(instance, {:start_service, deploy_ref})
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
  defp global_name(instance: instance), do: {:global, %{module: __MODULE__, instance: instance}}
  defp global_name(instance), do: {:global, %{module: __MODULE__, instance: instance}}

  def trigger_run_service(deploy_ref, timeout \\ 1),
    do: Process.send_after(self(), {:run_service, deploy_ref}, timeout)

  # NOTE: This function needs to use try/catch because rescue (suggested by credo)
  #       doesn't handle :exit
  defp call_gen_server(instance, message) do
    try do
      GenServer.call(global_name(instance), message)
    catch
      _, _ ->
        {:error, :rescued}
    end
  end

  defp run_service(%__MODULE__{instance: instance, deploy_ref: deploy_ref} = state, version_map) do
    executable = executable_path(instance)
    pre_commands = version_map["pre_commands"]
    version = version_map["version"]

    execute_pre_commands = fn ->
      Enum.each(pre_commands, fn command ->
        Logger.info(" # Running pre-command: #{command}")

        {:ok, _} =
          :exec.run_link(run_app_bin(instance, command), [
            :sync,
            {:stdout, AppConfig.stdout_path(instance)},
            {:stderr, AppConfig.stderr_path(instance)}
          ])
      end)
    end

    if File.exists?(executable) do
      Logger.info(" # Identified executable: #{executable}")

      execute_pre_commands.()

      Logger.info(" # Starting application")

      {:ok, pid, os_pid} =
        :exec.run_link(run_app_bin(instance), [
          {:stdout, AppConfig.stdout_path(instance)},
          {:stderr, AppConfig.stderr_path(instance)}
        ])

      Logger.info(
        " # Running instance: #{instance}, monitoring pid = #{inspect(pid)}, OS process = #{os_pid} deploy_ref: #{Common.short_ref(deploy_ref)}."
      )

      Process.send_after(self(), {:check_running, pid, deploy_ref}, @timeout_to_verify_app_ready)

      %{state | current_pid: pid, status: :starting, start_time: now()}
    else
      Logger.error("Version: #{version} set but no #{executable}")

      reset_state(state)
    end
  end

  # NOTE: Some commands need to run prior starting the application
  #       - Unset env vars from the deployex release to not mix with the monitored app release
  #       - Export suffix to add different snames to the apps
  #       - Export phoenix listening port taht needs to be one per app
  defp run_app_bin(instance, command \\ "start") do
    phx_port = AppConfig.phx_start_port() + (instance - 1)
    executable_path = executable_path(instance)

    """
    unset $(env | grep RELEASE | awk -F'=' '{print $1}')
    export RELEASE_NODE_SUFFIX=-#{instance}
    export PORT=#{phx_port}
    #{executable_path} #{command}
    """
  end

  defp executable_path(instance) do
    "#{AppConfig.current_path(instance)}/bin/#{AppConfig.monitored_app()}"
  end

  defp cleanup_beam_process(instance) do
    case :exec.run(
           "kill -9 $(ps -ax | grep \"#{AppConfig.monitored_app()}/#{instance}/current/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
           [:sync, :stdout, :stderr]
         ) do
      {:ok, _} ->
        Logger.warning("Remaining beam app removed for instance: #{instance}")

      {:error, _reason} ->
        # Logger.warning("Nothing to remove for instance: #{instance} - #{inspect(reason)}")
        :ok
    end
  end

  defp now, do: System.monotonic_time()

  defp reset_state(state, deploy_ref \\ nil),
    do: %{
      state
      | status: :idle,
        current_pid: nil,
        restarts: 0,
        start_time: nil,
        deploy_ref: deploy_ref
    }
end
