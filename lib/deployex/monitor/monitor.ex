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
    name = global_name(Keyword.get(args, :instance))
    GenServer.start_link(__MODULE__, args, name: {:global, name})
  end

  @impl true
  def init(instance: instance, deploy_ref: deploy_ref) do
    Process.flag(:trap_exit, true)

    Logger.info("Initialising monitor server for instance: #{instance}")

    Logger.metadata(instance: instance)

    trigger_run_service(deploy_ref)

    {:ok, reset_state(%__MODULE__{instance: instance}, deploy_ref)}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
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

  def handle_call({:run_pre_commands, pre_commands, app_bin_path}, _from, state) do

    execute_pre_commands(state.instance, pre_commands, app_bin_path)

    {:reply, {:ok, pre_commands}, state}
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

  def handle_info({:EXIT, _pid, :normal}, state) do
    # Ignore any erl_exec application that terminates normally, as this
    # occurs because the process is trapping all exits, including those
    # that are expected.
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

  @spec state(integer()) :: {:ok, %__MODULE__{}} | {:error, :rescued}
  def state(instance) do
    instance
    |> global_name()
    |> Common.call_gen_server(:state)
  end

  @spec run_pre_commands(integer(), list(), :new | :current) :: {:ok, list()} | {:error, :rescued}
  def run_pre_commands(instance, pre_commands, app_bin_path) do
    instance
    |> global_name()
    |> Common.call_gen_server({:run_pre_commands, pre_commands, app_bin_path})
  end

  @spec global_name(integer()) :: map()
  def global_name(instance), do: %{module: __MODULE__, instance: instance}

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  def trigger_run_service(deploy_ref, timeout \\ 1),
    do: Process.send_after(self(), {:run_service, deploy_ref}, timeout)

  defp run_service(%__MODULE__{instance: instance, deploy_ref: deploy_ref} = state, version_map) do
    app_exec = executable_path(instance, :current)
    version = version_map["version"]

    if File.exists?(app_exec) do
      Logger.info(" # Identified executable: #{app_exec}")

      execute_pre_commands(instance, version_map["pre_commands"], :current)

      Logger.info(" # Starting application")

      {:ok, pid, os_pid} =
        :exec.run_link(
          run_app_bin(instance, app_exec, "start"),
          [
            {:stdout, AppConfig.stdout_path(instance)},
            {:stderr, AppConfig.stderr_path(instance)}
          ]
        )

      Logger.info(
        " # Running instance: #{instance}, monitoring pid = #{inspect(pid)}, OS process = #{os_pid} deploy_ref: #{Common.short_ref(deploy_ref)}."
      )

      Process.send_after(self(), {:check_running, pid, deploy_ref}, @timeout_to_verify_app_ready)

      %{state | current_pid: pid, status: :starting, start_time: now()}
    else
      Logger.error("Version: #{version} set but no #{app_exec}")

      reset_state(state)
    end
  end

  # NOTE: Some commands need to run prior starting the application
  #       - Unset env vars from the deployex release to not mix with the monitored app release
  #       - Export suffix to add different snames to the apps
  #       - Export phoenix listening port taht needs to be one per app
  defp run_app_bin(instance, executable_path, command) do
    phx_port = AppConfig.phx_start_port() + (instance - 1)

    """
    unset $(env | grep RELEASE | awk -F'=' '{print $1}')
    export RELEASE_NODE_SUFFIX=-#{instance}
    export PORT=#{phx_port}
    #{executable_path} #{command}
    """
  end

  defp executable_path(instance, :current) do
    "#{AppConfig.current_path(instance)}/bin/#{AppConfig.monitored_app()}"
  end

  defp executable_path(instance, :new) do
    "#{AppConfig.new_path(instance)}/bin/#{AppConfig.monitored_app()}"
  end

  def execute_pre_commands(_instance, pre_commands, _bin_path) when pre_commands == [], do: :ok

  def execute_pre_commands(instance, pre_commands, bin_path) do
    migration_exec = executable_path(instance, bin_path)

    if File.exists?(migration_exec) do
      Logger.info(" # Migration executable: #{migration_exec}")

      Enum.each(pre_commands, fn command ->
        Logger.info(" # Running pre-command: #{command}")

        {:ok, _} =
          :exec.run_link(run_app_bin(instance, migration_exec, command), [
            :sync,
            {:stdout, AppConfig.stdout_path(instance)},
            {:stderr, AppConfig.stderr_path(instance)}
          ])
      end)
    end

    :ok
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
