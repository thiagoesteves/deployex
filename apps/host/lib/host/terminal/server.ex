defmodule Host.Terminal.Server do
  @moduledoc false
  use GenServer
  require Logger

  alias Host.Commander

  defmodule Message do
    @moduledoc """
    Structure to encapsulate the message that will be sent to the target process
    """
    @type t :: %__MODULE__{
            metadata: any(),
            node: node() | nil,
            source_pid: pid() | nil,
            process: pid() | nil,
            msg_sequence: integer(),
            status: :open | :closed,
            message: String.t() | nil
          }

    @derive Jason.Encoder

    defstruct metadata: nil,
              node: nil,
              source_pid: nil,
              process: nil,
              msg_sequence: 0,
              status: :open,
              message: nil
  end

  @default_terminal_timeout_session_ms 300_000

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  @spec init(any()) :: {:ok, any(), {:continue, :open_erlexec_connection}}
  def init(state) do
    state =
      state
      |> Map.put(
        :timeout_session,
        state.timeout_session || @default_terminal_timeout_session_ms
      )
      |> Map.put(:source_pid, self())

    if state.timeout_session != :infinity,
      do: Process.send_after(self(), :session_timeout, state.timeout_session)

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
  def handle_continue(:open_erlexec_connection, %{node: node, metadata: metadata} = state) do
    case Commander.run(state.commands, state.options) do
      {:ok, _pid, process} ->
        message =
          "Initializing Terminal node: #{node} - #{inspect(metadata)} at process os_pid: #{process}"

        Logger.info(message)

        state = %{state | message: "", process: process}

        # NOTE: Send at least one message to sync with the target process
        notify_target(state)

        {:noreply, state}

      reason ->
        Logger.error(
          "Error while trying to run the commands for node: #{node} - #{inspect(metadata)}, reason: #{inspect(reason)}"
        )

        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_cast(:terminate, %{process: process} = state) do
    state = %{state | status: :closed}

    # Stop OS process
    Commander.stop(process)

    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:session_timeout, %{process: process} = state) do
    state = %{state | status: :closed}
    notify_target(state)

    # Stop OS process
    Commander.stop(process)

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
        {:DOWN, _os_pid, :process, target_pid, reason},
        %{process: process, target: target} = state
      )
      when target_pid == target do
    state = %{state | status: :closed}

    # Stop OS process
    Commander.stop(process)

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

  @spec async_terminate(pid()) :: :ok
  def async_terminate(pid) do
    GenServer.cast(pid, :terminate)
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================
  defp notify_target(state) do
    send(
      state.target,
      {:terminal_update,
       %Host.Terminal.Server.Message{
         metadata: state.metadata,
         source_pid: state.source_pid,
         node: state.node,
         process: state.process,
         msg_sequence: state.msg_sequence,
         status: state.status,
         message: state.message
       }}
    )
  end
end
