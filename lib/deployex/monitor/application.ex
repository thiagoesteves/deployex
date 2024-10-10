defmodule Deployex.Monitor.Application do
  @moduledoc """
  GenServer that monitor and supervise the application.
  """
  use GenServer
  require Logger

  alias Deployex.Common
  alias Deployex.Deployment
  alias Deployex.OpSys
  alias Deployex.Status
  alias Deployex.Storage

  @behaviour Deployex.Monitor.Adapter

  @monitor_table "monitor-table"

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    name = global_name(Keyword.get(args, :instance))
    GenServer.start_link(__MODULE__, args, name: {:global, name})
  end

  @impl true
  def init(
        instance: instance,
        deploy_ref: deploy_ref,
        timeout_app_ready: timeout_app_ready,
        retry_delay_pre_commands: retry_delay_pre_commands
      ) do
    Process.flag(:trap_exit, true)

    # NOTE: This ETS table provides non-blocking access to the state.
    instance
    |> table_name()
    |> String.to_atom()
    |> :ets.new([:set, :protected, :named_table])

    Logger.info("Initialising monitor server for instance: #{instance}")

    trigger_run_service(deploy_ref)

    initial_state =
      reset_state(
        %Deployex.Monitor{
          instance: instance,
          timeout_app_ready: timeout_app_ready,
          retry_delay_pre_commands: retry_delay_pre_commands
        },
        deploy_ref
      )

    {:ok, update_non_blocking_state(initial_state)}
  end

  @impl true
  def handle_call(
        :stop_service,
        _from,
        %Deployex.Monitor{current_pid: current_pid, instance: instance} = state
      )
      when is_nil(current_pid) do
    Logger.warning("Requested instance: #{instance} to stop but application is not running.")

    {:reply, :ok, state}
  end

  def handle_call(
        :stop_service,
        _from,
        %Deployex.Monitor{instance: instance, current_pid: pid} = state
      ) do
    Logger.info("Requested instance: #{instance} to stop application pid: #{inspect(pid)}")

    # Stop current application
    OpSys.stop(state.current_pid)

    # NOTE: The next command is needed for Systems that have a different PID for the "/bin/app start" script
    #       and the bin/beam.smp process
    cleanup_beam_process(state.instance)

    state = reset_state(state)

    {:reply, :ok, update_non_blocking_state(state)}
  end

  # This command is available during the hot upgrade. If it fails, the process will
  # restart and attempt a full deployment.
  def handle_call({:run_pre_commands, pre_commands, app_bin_path}, _from, state) do
    :ok = execute_pre_commands(state, pre_commands, app_bin_path)

    {:reply, {:ok, pre_commands}, state}
  end

  def handle_call(:restart, _from, state) when is_nil(state.current_pid) do
    {:reply, {:error, :application_is_not_running}, state}
  end

  def handle_call(:restart, _from, state) do
    Logger.warning("Restart requested for instance: #{state.instance}")

    # Stop current application
    OpSys.stop(state.current_pid)

    cleanup_beam_process(state.instance)

    # Update the number of force restarts
    force_restart_count = state.force_restart_count + 1

    # Retry with backoff pattern
    trigger_run_service(state.deploy_ref)

    {:reply, :ok, update_non_blocking_state(%{state | force_restart_count: force_restart_count})}
  end

  @impl true
  def handle_info({:run_service, deploy_ref}, %Deployex.Monitor{instance: instance} = state)
      when deploy_ref == state.deploy_ref do
    version_map = Status.current_version_map(state.instance)
    version = version_map.version

    state =
      if version == nil do
        Logger.info("No version set, not able to run_service")
        state
      else
        Logger.info("Ensure running requested for instance: #{instance} version: #{version}")

        run_service(state, version_map)
      end

    {:noreply, update_non_blocking_state(state)}
  end

  def handle_info({:check_running, pid, deploy_ref}, state)
      when pid == state.current_pid and deploy_ref == state.deploy_ref do
    Logger.info(" # Application instance: #{state.instance} is running")

    Deployment.notify_application_running(state.instance, deploy_ref)

    {:noreply, update_non_blocking_state(%{state | status: :running})}
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

    # Update the number of crash restarts
    crash_restart_count = state.crash_restart_count + 1

    # Retry with backoff pattern
    trigger_run_service(state.deploy_ref, 2 * crash_restart_count * 1000)

    {:noreply, update_non_blocking_state(%{state | crash_restart_count: crash_restart_count})}
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
  @impl true
  def state(instance) do
    [{_, value}] =
      instance
      |> table_name()
      |> String.to_existing_atom()
      |> :ets.lookup(instance)

    value
  rescue
    _ ->
      %Deployex.Monitor{}
  end

  @impl true
  def run_pre_commands(instance, pre_commands, app_bin_path) do
    instance
    |> global_name()
    |> Common.call_gen_server({:run_pre_commands, pre_commands, app_bin_path})
  end

  @impl true
  defdelegate start_service(instance, deploy_ref, options \\ []), to: Deployex.Monitor.Supervisor

  @impl true
  defdelegate stop_service(instance), to: Deployex.Monitor.Supervisor

  @impl true
  def restart(instance) do
    instance
    |> global_name()
    |> Common.call_gen_server(:restart)
  end

  @impl true
  def global_name(instance), do: %{node: Node.self(), module: __MODULE__, instance: instance}

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  def trigger_run_service(deploy_ref, timeout \\ 1),
    do: Process.send_after(self(), {:run_service, deploy_ref}, timeout)

  defp run_service(
         %Deployex.Monitor{
           instance: instance,
           deploy_ref: deploy_ref,
           timeout_app_ready: timeout_app_ready,
           retry_delay_pre_commands: retry_delay_pre_commands
         } = state,
         version_map
       ) do
    app_exec = executable_path(instance, :current)
    version = version_map.version

    with true <- File.exists?(app_exec),
         :ok <- Logger.info(" # Identified executable: #{app_exec}"),
         :ok <- execute_pre_commands(state, version_map.pre_commands, :current) do
      Logger.info(" # Starting application")

      {:ok, pid, os_pid} =
        OpSys.run_link(
          run_app_bin(instance, app_exec, "start"),
          [
            {:stdout, Storage.stdout_path(instance) |> to_charlist, [:append, {:mode, 0o600}]},
            {:stderr, Storage.stderr_path(instance) |> to_charlist, [:append, {:mode, 0o600}]}
          ]
        )

      log_message =
        " # Running instance: #{instance}, monitoring pid = #{inspect(pid)}, OS process = #{os_pid} deploy_ref: #{deploy_ref}"

      Logger.info(log_message)

      Process.send_after(self(), {:check_running, pid, deploy_ref}, timeout_app_ready)

      %{state | current_pid: pid, status: :starting, start_time: now()}
    else
      false ->
        trigger_run_service(deploy_ref, retry_delay_pre_commands)
        Logger.error("Version: #{version} set but no #{app_exec}")
        state

      {:error, :pre_commands} ->
        trigger_run_service(deploy_ref, retry_delay_pre_commands)
        %{state | status: :pre_commands}
    end
  end

  # NOTE: Some commands need to run prior starting the application
  #       - Unset env vars from the deployex release to not mix with the monitored app release
  #       - Export suffix to add different snames to the apps
  #       - Export phoenix listening port taht needs to be one per app
  defp run_app_bin(instance, executable_path, command) do
    phx_port = Storage.phx_start_port() + (instance - 1)

    """
    unset $(env | grep RELEASE | awk -F'=' '{print $1}')
    export RELEASE_NODE_SUFFIX=-#{instance}
    export PORT=#{phx_port}
    #{executable_path} #{command}
    """
  end

  defp executable_path(instance, :current) do
    "#{Storage.current_path(instance)}/bin/#{Storage.monitored_app()}"
  end

  defp executable_path(instance, :new) do
    "#{Storage.new_path(instance)}/bin/#{Storage.monitored_app()}"
  end

  # credo:disable-for-lines:28
  defp execute_pre_commands(_state, pre_commands, _bin_path) when pre_commands == [], do: :ok

  defp execute_pre_commands(%{instance: instance, status: status} = state, pre_commands, bin_path) do
    migration_exec = executable_path(instance, bin_path)

    update_non_blocking_state(%{state | status: :pre_commands})

    if File.exists?(migration_exec) do
      Logger.info(" # Migration executable: #{migration_exec}")

      Enum.reduce_while(pre_commands, :ok, fn pre_command, acc ->
        Logger.info(" # Executing: #{pre_command}")

        OpSys.run(run_app_bin(instance, migration_exec, pre_command), [
          :sync,
          {:stdout, Storage.stdout_path(instance) |> to_charlist, [:append, {:mode, 0o600}]},
          {:stderr, Storage.stderr_path(instance) |> to_charlist, [:append, {:mode, 0o600}]}
        ])
        |> case do
          {:ok, _} ->
            {:cont, acc}

          {:error, reason} ->
            Logger.error(
              "Error running pre-command: #{pre_command} for instance: #{instance} reason: #{inspect(reason)}"
            )

            {:halt, {:error, :pre_commands}}
        end
      end)
    else
      {:error, :migration_exec_non_available}
    end
    |> tap(fn _response -> update_non_blocking_state(%{state | status: status}) end)
  end

  defp cleanup_beam_process(instance) do
    case OpSys.run(
           "kill -9 $(ps -ax | grep \"#{Storage.monitored_app()}/#{instance}/current/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
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
        crash_restart_count: 0,
        force_restart_count: 0,
        start_time: nil,
        deploy_ref: deploy_ref
    }

  defp table_name(instance), do: @monitor_table <> "-#{instance}"

  defp update_non_blocking_state(%{instance: instance} = state) do
    instance
    |> table_name()
    |> String.to_existing_atom()
    |> :ets.insert({instance, state})

    state
  end
end
