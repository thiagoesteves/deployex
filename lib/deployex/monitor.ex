defmodule Deployex.Monitor do
  @moduledoc """
  GenServer that monitor and supervise the application.
  """
  use GenServer
  require Logger

  alias Deployex.{Configuration, State}

  # Since we are running from another release, the deployer RELEASE_* vars need to be unset"
  @unset_release_vars " unset $(env | grep RELEASE | awk -F'=' '{print $1}') ; "

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any(), atom() | {:global, any()} | {:via, atom(), any()}) ::
          :ignore | {:error, any()} | {:ok, pid()}
  def start_link(arg, name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, arg, name: name)
  end

  @impl true
  def init(_arg) do
    Process.flag(:trap_exit, true)

    state = start_service(State.current_version(), %{current_pid: nil})
    {:ok, state}
  end

  @impl true
  def handle_call(:start_service, _from, state) do
    state = start_service(State.current_version(), state)
    {:reply, :ok, state}
  end

  def handle_call(:current_pid, _from, %{current_pid: current_pid} = state) do
    {:reply, current_pid, state}
  end

  def handle_call(:stop_service, _from, state) when is_nil(state.current_pid) do
    Logger.info("Requested to stop but application is not running.")
    {:reply, :ok, state}
  end

  def handle_call(:stop_service, _from, %{current_pid: current_pid} = state)
      when is_nil(current_pid) do
    {:reply, :ok, state}
  end

  def handle_call(:stop_service, _from, %{current_pid: current_pid} = state) do
    Logger.info("Requested to stop application pid: #{inspect(current_pid)}")

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
  def handle_info({:EXIT, pid, reason}, %{current_pid: current_pid} = state) do
    state =
      if current_pid == pid do
        Logger.error("Unexpected exit message received from pid: #{inspect(pid)} being restarted")
        start_service(State.current_version(), state)
      else
        Logger.warning(
          "Application with pid: #{inspect(pid)} - state: #{inspect(state)} being stopped by reason: #{inspect(reason)}"
        )

        state
      end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================

  @spec start_service() :: any()
  def start_service do
    GenServer.call(__MODULE__, :start_service)
  end

  @spec stop_service() :: :ok
  def stop_service do
    :ok = GenServer.call(__MODULE__, :stop_service)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp start_service(nil, state) do
    Logger.info("No version set, not able to start_service")
    state
  end

  defp start_service(version, state) do
    Logger.info("Ensure running requested for version: #{version}")

    executable = executable_path()

    if File.exists?(executable) do
      Logger.info(" - Starting #{executable}...")

      {:ok, pid, os_pid} =
        :exec.run_link(@unset_release_vars <> executable <> " start", [
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

  defp executable_path do
    Path.join([Configuration.current_path(), "bin", Configuration.monitored_app()])
  end

  defp stdout_path,
    do: "#{Configuration.log_path()}/#{Configuration.monitored_app()}-stdout.log"

  defp stderr_path,
    do: "#{Configuration.log_path()}/#{Configuration.monitored_app()}-stderr.log"
end
