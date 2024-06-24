defmodule Deployex.Terminal.Server do
  @moduledoc false
  use GenServer
  require Logger

  defstruct commands: nil,
            type: nil,
            process: nil,
            msg_sequence: 0,
            instance: "",
            target: nil,
            status: :open,
            message: nil

  @default_terminal_timeout_session_ms 300_000

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: global_name(args))
  end

  @impl true
  @spec init(any()) :: {:ok, any(), {:continue, :open_erlexec_connection}}
  def init(state) do
    Process.send_after(self(), :session_timeout, @default_terminal_timeout_session_ms)

    Process.monitor(state.target)

    {:ok, state, {:continue, :open_erlexec_connection}}
  end

  @impl true
  def handle_continue(:open_erlexec_connection, %__MODULE__{commands: commands} = state) do
    {:ok, _pid, process} = :exec.run(commands, [:stdin, :stdout, :pty, :pty_echo, :monitor])

    {:noreply, %{state | process: process}}
  end

  @impl true
  def handle_cast(:terminate, state) do
    state = %{state | status: :closed}
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:session_timeout, state) do
    state = %{state | status: :closed}
    notify_target(state)
    Logger.debug("The terminal session timed out")
    {:stop, :normal, state}
  end

  def handle_info({:stdout, os_process, message}, %{process: process} = state)
      when os_process == process do
    state = %{state | msg_sequence: state.msg_sequence + 1, message: message}

    notify_target(state)

    {:noreply, state}
  end

  # NOTE: Target process was terminated
  def handle_info({:DOWN, _ref, :process, _pid, {:shutdown, :closed}}, state) do
    state = %{state | status: :closed}
    Logger.debug("The Target process was terminated")
    {:stop, :normal, state}
  end

  # NOTE: OS process was terminated
  def handle_info({:DOWN, _ref, :process, _pid, {:exit_status, _}}, state) do
    state = %{state | status: :closed}
    Logger.debug("The erlexec process was terminated")
    notify_target(state)
    {:stop, :normal, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  def async_terminate(%__MODULE__{} = args) do
    GenServer.cast(global_name(args), :terminate)
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================
  defp notify_target(state) do
    send(state.target, {:terminal_update, state})
  end

  defp global_name(%{instance: instance, type: type}),
    do: {:global, %{instance: instance, type: type}}
end
