defmodule Deployex.Tracer.Server do
  @moduledoc """
  This server is responsible for handling tracing requests.

  Inspired by:
   * https://www.erlang.org/docs/24/man/dbg
   * https://github.com/erlang/otp/blob/master/lib/observer/src/observer_trace_wx.erl
   * https://kaiwern.com/posts/2020/11/02/debugging-with-tracing-in-elixir/
   * https://blog.appsignal.com/2023/01/10/debugging-and-tracing-in-erlang.html
  """
  use GenServer
  require Logger

  alias Deployex.Common
  alias Deployex.Tracer, as: DeployexT

  ### ==========================================================================
  ### GenServer Callbacks
  ### ==========================================================================
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Logger.info("Initializing Tracing Server")
    {:ok, %DeployexT{}}
  end

  @impl true
  def handle_call(
        {:start_trace, _functions, _session_timeout_ms},
        _from,
        %DeployexT{status: :running} = state
      ) do
    {:reply, {:error, :already_started}, state}
  end

  def handle_call({:stop_tracing, rcv_session_id}, _from, %DeployexT{
        session_id: session_id
      })
      when rcv_session_id == session_id do
    Logger.info("The Trace session_id: #{inspect(session_id)} was requested to stop.")

    :dbg.stop()

    {:reply, :ok, %DeployexT{}}
  end

  def handle_call({:stop_tracing, _rcv_session_id}, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(
        {:start_trace,
         %{
           max_messages: max_messages,
           session_id: session_id,
           request_pid: request_pid,
           functions_by_node: functions_by_node,
           session_timeout_ms: session_timeout_ms
         } = new_state},
        _from,
        _state
      ) do
    Logger.warning(
      "New trace requested session: #{session_id} functions: #{inspect(functions_by_node)}"
    )

    tracer_pid = self()
    # The local node (deployex) is always present in the trace list of nodes.
    # The following list will indicate to the trace handler whether the node
    # should be included or filtered out.
    monitored_nodes = Map.keys(functions_by_node)

    handle_trace = fn
      {_, pid, _, {module, fun, args}, timestamp}, {session_id, index}
      when index <= max_messages ->
        node = :erlang.node(pid)

        if node in monitored_nodes do
          {{y, mm, d}, {h, m, s}} = :calendar.now_to_datetime(timestamp)
          arg_list = Enum.map(args, &inspect/1)

          message =
            "[#{y}-#{mm}-#{d} #{h}:#{m}:#{s}] (#{inspect(pid)}) #{inspect(module)}.#{fun}(#{Enum.join(arg_list, ", ")})"

          send(request_pid, {:new_trace_message, session_id, node, index, message})

          if index == max_messages do
            send(tracer_pid, {:stop_tracing, session_id})
            send(request_pid, {:stop_tracing, session_id})
            :dbg.stop()
          end

          {session_id, index + 1}
        else
          {session_id, index}
        end

      _trace_message, _session_index ->
        :dbg.stop()
    end

    # Start Tracer with Handler Function
    :dbg.tracer(:process, {handle_trace, {session_id, 1}})

    Enum.each(functions_by_node, fn {node, functions} ->
      # Add node to tracing process (exclude local node since it is added by default)
      if node != Node.self() do
        :dbg.n(node)
      end

      # Add functions to be traced
      Enum.each(functions, fn function ->
        :dbg.tp(function.module, function.function, function.arity, [])
      end)
    end)

    # :all -> All processes and ports in the system as well as all processes and ports
    #         created hereafter are to be traced.
    # :c -> Traces global function calls for the process according to the trace patterns
    #       set in the system (see tp/2).
    :dbg.p(:all, [:c, :timestamp])

    Process.send_after(self(), {:trace_session_timeout, session_id}, session_timeout_ms)

    new_state = %{new_state | status: :running}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_info(
        {:trace_session_timeout, session_id_timed_out},
        %DeployexT{session_id: session_id} = state
      )
      when session_id != session_id_timed_out do
    {:noreply, state}
  end

  def handle_info({:trace_session_timeout, rcv_session_id} = msg, %DeployexT{
        session_id: session_id,
        request_pid: request_pid
      })
      when rcv_session_id == session_id do
    Logger.info("The Trace session_id: #{inspect(session_id)} timed out")

    :dbg.stop()

    send(request_pid, msg)

    {:noreply, %DeployexT{}}
  end

  def handle_info({:trace_session_timeout, _rcv_session_id}, state) do
    {:noreply, state}
  end

  def handle_info({:stop_tracing, rcv_session_id} = msg, %DeployexT{
        session_id: session_id,
        max_messages: max_messages,
        request_pid: request_pid
      })
      when rcv_session_id == session_id do
    Logger.info("Max messages (#{max_messages}) reached for session: #{inspect(session_id)}.")

    send(request_pid, msg)

    {:noreply, %DeployexT{}}
  end

  def handle_info({:stop_tracing, _session_id}, state) do
    {:noreply, state}
  end

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================

  @spec start_trace(functions :: list(), attrs :: map()) ::
          {:ok, DeployexT.t()} | {:error, :already_started}
  def start_trace(functions, attrs) do
    GenServer.call(
      __MODULE__,
      {:start_trace,
       struct(
         DeployexT,
         attrs
         |> Map.put(:request_pid, self())
         |> Map.put(:session_id, Common.uuid4())
         |> Map.put(:functions_by_node, Enum.group_by(functions, & &1.node))
       )}
    )
  end

  @spec stop_trace(binary()) :: :ok
  def stop_trace(session_id) do
    GenServer.call(__MODULE__, {:stop_tracing, session_id})
  end

  @spec state :: DeployexT.t()
  def state do
    GenServer.call(__MODULE__, :state)
  end

  ### ==========================================================================
  ### Private Functions
  ### ==========================================================================
end
