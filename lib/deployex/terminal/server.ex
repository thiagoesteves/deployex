defmodule Deployex.Terminal.Server do
  @moduledoc false
  use GenServer
  require Logger

  alias Deployex.OpSys

  defstruct commands: nil,
            type: nil,
            process: nil,
            msg_sequence: 0,
            instance: "",
            target: nil,
            status: :open,
            message: nil,
            options: [],
            timeout_session: nil

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
    state =
      Map.put(
        state,
        :timeout_session,
        state.timeout_session || @default_terminal_timeout_session_ms
      )

    Process.send_after(self(), :session_timeout, state.timeout_session)

    Process.monitor(state.target)

    # Since the GenServer will always monitor, check that the flag is present or add otherwise
    state =
      if Enum.member?(state.options, :monitor) do
        state
      else
        %{state | options: [:monitor | state.options]}
      end

    {:ok, state, {:continue, :open_erlexec_connection}}
  end

  @impl true
  def handle_continue(:open_erlexec_connection, state) do
    case OpSys.run(state.commands, state.options) do
      {:ok, _pid, process} ->
        Logger.info(
          "Initializing terminal instance: #{state.instance} at process pid: #{process}"
        )

        state = %{state | message: "", process: process}

        # NOTE: Send at least one message to sync with the target process
        notify_target(state)

        {:noreply, state}

      reason ->
        Logger.error(
          "Error while trying to run the commands for instance: #{state.instance}, reason: #{inspect(reason)}"
        )

        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_cast(:terminate, %{process: process} = state) do
    state = %{state | status: :closed}

    # Stop OS process
    OpSys.stop(process)

    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:session_timeout, %{process: process} = state) do
    state = %{state | status: :closed}
    notify_target(state)

    # Stop OS process
    OpSys.stop(process)

    Logger.info("The terminal session timed out")
    {:stop, :normal, state}
  end

  def handle_info({:stdout, os_process, message}, %{process: process} = state)
      when os_process == process do
    state = %{state | msg_sequence: state.msg_sequence + 1, message: message}

    notify_target(state)

    {:noreply, state}
  end

  # NOTE: Target process was terminated
  def handle_info(
        {:DOWN, _ref, :process, target_pid, reason},
        %{process: process, target: target} = state
      )
      when target_pid == target do
    state = %{state | status: :closed}

    # Stop OS process
    OpSys.stop(process)

    Logger.warning(
      "The Target process state: #{inspect(state)} was terminated, reason: #{inspect(reason)}"
    )

    {:stop, :normal, state}
  end

  # NOTE: OS process was terminated
  def handle_info({:DOWN, os_pid, :process, _pid, reason}, %{process: process} = state)
      when os_pid == process do
    state = %{state | status: :closed}

    Logger.warning(
      "The erlexec process: #{inspect(state)} was terminated, reason: #{inspect(reason)}"
    )

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
