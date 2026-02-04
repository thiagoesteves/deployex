defmodule Sentinel.Logs.AsyncRead do
  @moduledoc """
  GenServer that collects and store the logs received
  """
  use GenServer

  require Logger

  @default_timeout 10_000
  @one_minute_in_milliseconds 60_000

  @type t :: %__MODULE__{
          session: String.t() | nil,
          session_state: :open | :closed,
          sname: String.t() | nil,
          log_type: String.t() | nil,
          order: :desc | :asc,
          from: non_neg_integer(),
          read_from_list: list(),
          target_pid: pid() | nil,
          sname_table: atom() | nil,
          timeout_session: non_neg_integer()
        }

  defstruct session: nil,
            session_state: :open,
            sname: nil,
            log_type: nil,
            order: :desc,
            from: 0,
            read_from_list: [],
            target_pid: nil,
            sname_table: nil,
            timeout_session: @default_timeout

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================
  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    state = struct(%__MODULE__{}, args |> Enum.into(%{}))
    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(%__MODULE__{} = state) do
    Process.send_after(self(), :async_read_session_timeout, state.timeout_session)

    now_minutes = unix_to_minutes()
    from_minutes = now_minutes - state.from

    sname_table = sname_log_table(state.sname)

    read_from_list =
      case state.order do
        :asc ->
          Enum.into(from_minutes..now_minutes, [])

        :desc ->
          Enum.into(now_minutes..from_minutes, [])
      end

    Process.monitor(state.target_pid)

    # Subscribe Server to listen to events based on session id
    Phoenix.PubSub.subscribe(Sentinel.PubSub, logs_async_topic(state.session))

    {:ok, %{state | sname_table: sname_table, read_from_list: read_from_list},
     {:continue, :async_read_ack}}
  end

  @impl true
  def handle_continue(:async_read_ack, state), do: handle_ack(state)

  @impl true
  def handle_info(:async_read_ack, state), do: handle_ack(state)

  def handle_info(
        {:DOWN, _os_pid, :process, target_pid, _reason},
        %{target_pid: target} = state
      )
      when target_pid == target do
    {:stop, :normal, %{state | session_state: :closed}}
  end

  def handle_info(:async_read_session_timeout, state) do
    Logger.info("timeout")
    {:stop, :normal, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  def ack(session_id) do
    Phoenix.PubSub.broadcast(Deployer.PubSub, logs_async_topic(session_id), :async_read_ack)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp sname_log_table(sname), do: String.to_atom("deployex-logs::#{sname}")

  defp log_type_key(type, timestamp), do: "#{type}|#{timestamp}"

  defp unix_to_minutes(time \\ System.os_time(:millisecond)),
    do: trunc(time / @one_minute_in_milliseconds)

  defp logs_async_topic(session), do: "deployex-logs::async_read::#{session}"

  defp handle_ack(%__MODULE__{read_from_list: []} = state) do
    Logger.info("No more reads")
    state = %{state | session_state: :closed}

    send_values(state, [])
    {:stop, :normal, %{state | session_state: :closed}}
  end

  defp handle_ack(
         %__MODULE__{
           sname_table: sname_table,
           log_type: type,
           order: order,
           read_from_list: [head | rest]
         } = state
       ) do
    Logger.info("ACK")

    values =
      case :ets.lookup(sname_table, log_type_key(type, head)) do
        [{_, values}] ->
          if order == :asc, do: Enum.reverse(values), else: values

        _ ->
          []
      end

    if rest == [] do
      state = %{state | read_from_list: rest, session_state: :closed}

      send_values(state, values)
      {:stop, :normal, state}
    else
      state = %{state | read_from_list: rest}

      send_values(state, values)
      {:noreply, state}
    end
  end

  defp send_values(%{session: session, session_state: state, target_pid: pid}, values) do
    send(pid, {:logs_async_read, session, state, values})
  end
end
