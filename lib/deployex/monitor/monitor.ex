defmodule Deployex.Monitor do
  @moduledoc """
  GenServer that monitor and supervise the application.
  """
  use GenServer
  require Logger

  alias Deployex.{AppStatus, Configuration}

  defstruct current_pid: nil,
            instance: nil

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

    Logger.metadata(instance: instance)

    current_version = AppStatus.current_version(instance)

    state =
      %__MODULE__{instance: instance}
      |> run_service(current_version)

    {:ok, state}
  end

  @impl true
  def handle_call(:start_service, _from, %{instance: instance} = state) do
    current_version = AppStatus.current_version(instance)

    state = run_service(state, current_version)

    {:reply, :ok, state}
  end

  def handle_call(:current_pid, _from, %{current_pid: current_pid} = state) do
    {:reply, current_pid, state}
  end

  def handle_call(:stop_service, _from, %{current_pid: current_pid, instance: instance} = state)
      when is_nil(current_pid) do
    Logger.info("Requested instance: #{instance} to stop but application is not running.")
    {:reply, :ok, state}
  end

  def handle_call(:stop_service, _from, %{current_pid: current_pid} = state)
      when is_nil(current_pid) do
    {:reply, :ok, state}
  end

  def handle_call(:stop_service, _from, %{current_pid: current_pid, instance: instance} = state) do
    Logger.info(
      "Requested instance: #{instance} to stop application pid: #{inspect(current_pid)}"
    )

    # Stop current application
    :exec.stop(current_pid)

    # NOTE: The next command is needed for Systems that have a different PID for the "/bin/app start" script
    #       and the bin/beam.smp process
    :exec.run(
      "kill -9 $(ps -ax | grep \"#{Configuration.monitored_app()}/current/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
      [:sync, :stdout, :stderr]
    )

    {:reply, :ok, %{state | current_pid: nil}}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{current_pid: current_pid, instance: instance} = state) do
    state =
      if current_pid == pid do
        Logger.error(
          "Unexpected exit message received for instance: #{instance} from pid: #{inspect(pid)} being restarted"
        )

        current_version = AppStatus.current_version(instance)

        run_service(state, current_version)
      else
        Logger.warning(
          "Application instance: #{instance} with pid: #{inspect(pid)} - state: #{inspect(state)} being stopped by reason: #{inspect(reason)}"
        )

        state
      end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @spec start_service(integer()) :: any()
  def start_service(instance) do
    GenServer.call(global_name(instance), :start_service)
  end

  @spec stop_service(integer()) :: :ok
  def stop_service(instance) do
    :ok = GenServer.call(global_name(instance), :stop_service)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp global_name(instance: instance), do: {:global, %{instance: instance}}
  defp global_name(instance), do: {:global, %{instance: instance}}

  defp run_service(state, nil) do
    Logger.info("No version set, not able to run_service")
    state
  end

  defp run_service(%__MODULE__{instance: instance} = state, version) do
    Logger.info("Ensure running requested for instance: #{instance} version: #{version}")

    executable = executable_path(instance)

    if File.exists?(executable) do
      Logger.info(" - Starting #{executable}...")

      {:ok, pid, os_pid} =
        :exec.run_link(pre_commands(instance) <> executable <> " start", [
          {:stdout, stdout_path()},
          {:stderr, stderr_path()}
        ])

      Logger.info(" - Running, monitoring pid = #{inspect(pid)}, OS process id = #{os_pid}.")
      %{state | current_pid: pid}
    else
      Logger.error("Version set but no #{executable}")

      state
    end
  end

  # NOTE: Since we are running from another release, the deployer RELEASE_* vars need to be unset"
  defp pre_commands(instance) do
    phx_port = phx_start_port() + (instance - 1)

    "unset $(env | grep RELEASE | awk -F'=' '{print $1}') ; export RELEASE_NODE_SUFFIX=-#{instance}; export PORT=#{phx_port} ;"
  end

  defp executable_path(instance) do
    Path.join([Configuration.current_path(instance), "bin", Configuration.monitored_app()])
  end

  defp phx_start_port, do: Application.get_env(:deployex, :phx_start_port)

  defp stdout_path,
    do: "#{Configuration.log_path()}/#{Configuration.monitored_app()}-stdout.log"

  defp stderr_path,
    do: "#{Configuration.log_path()}/#{Configuration.monitored_app()}-stderr.log"
end
