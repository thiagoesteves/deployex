defmodule Deployer.SelfUpgrade.Worker do
  @moduledoc """
  Reconciles the running DeployEx version toward the desired version published by IaC.

  The upgrade itself shells out to `deployex.sh` and drives `release_handler` on this same
  node. That work runs in a supervised `Task`, not inside this GenServer, so the worker stays
  responsive to `sys` messages. That matters because a self-upgrade whose relup changes this
  very module calls `sys:suspend` on the worker: if the worker were blocked in the shell-out
  the suspend would time out, the process would be skipped, and a later purge could kill it
  mid-upgrade. A backstop timeout bounds a stuck attempt so the reconcile interval keeps
  running instead of wedging.
  """

  use GenServer
  require Logger

  alias Deployer.SelfUpgrade.Executor
  alias Deployer.SelfUpgrade.Source

  @task_supervisor Deployer.SelfUpgrade.TaskSupervisor
  @default_upgrade_timeout_ms :timer.minutes(10)

  defstruct interval_ms: 60_000,
            upgrade_timeout_ms: @default_upgrade_timeout_ms,
            last_failed: nil,
            timer: nil,
            task: nil,
            timeout_ref: nil,
            upgrading: nil

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Trigger a reconcile now. Returns immediately with the decision, never the upgrade result:
  `:noop` (no drift or already-failed version), `:started` (an upgrade Task was spawned), or
  `:in_progress` (an upgrade is already running). The upgrade runs asynchronously.
  """
  @spec reconcile(GenServer.server()) :: :noop | :started | :in_progress
  def reconcile(server \\ __MODULE__), do: GenServer.call(server, :reconcile)

  @impl true
  def init(opts) do
    state = %__MODULE__{
      interval_ms: Keyword.get(opts, :interval_ms, 60_000),
      upgrade_timeout_ms: Keyword.get(opts, :upgrade_timeout_ms, @default_upgrade_timeout_ms)
    }

    {:ok, schedule(state)}
  end

  @impl true
  def handle_call(:reconcile, _from, state) do
    {result, state} = maybe_start_upgrade(state)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_result, state} = maybe_start_upgrade(state)
    {:noreply, schedule(state)}
  end

  # The upgrade Task finished.
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish(result, state)}
  end

  # The upgrade Task crashed.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    {:noreply, finish({:error, {:task_down, reason}}, state)}
  end

  # A running upgrade exceeded its backstop timeout.
  def handle_info(:upgrade_timeout, %{task: %Task{} = task} = state) do
    Task.Supervisor.terminate_child(@task_supervisor, task.pid)
    Process.demonitor(task.ref, [:flush])

    Logger.error(
      "Self-upgrade: hot upgrade to #{state.upgrading} timed out, giving up this attempt"
    )

    {:noreply, finish({:error, :timeout}, %{state | timeout_ref: nil})}
  end

  # Stale messages (a timer or task reference from an attempt already finished).
  def handle_info(_msg, state), do: {:noreply, state}

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule(%{interval_ms: :never} = state), do: state

  defp schedule(state) do
    timer = Process.send_after(self(), :tick, state.interval_ms)
    %{state | timer: timer}
  end

  defp running_version, do: Application.spec(:foundation, :vsn) |> to_string()

  # An upgrade is already in flight: leave it alone (single-flight).
  defp maybe_start_upgrade(%{task: task} = state) when not is_nil(task), do: {:in_progress, state}

  defp maybe_start_upgrade(state) do
    case Source.desired_version() do
      {:ok, version} ->
        reconcile_version(version, state)

      :none ->
        {:noop, state}

      {:error, reason} ->
        Logger.warning("Self-upgrade: source error #{inspect(reason)}")
        {:noop, state}
    end
  end

  defp reconcile_version(version, state) do
    cond do
      version == running_version() -> {:noop, %{state | last_failed: nil}}
      version == state.last_failed -> {:noop, state}
      true -> start_upgrade(version, state)
    end
  end

  defp start_upgrade(version, state) do
    emit(:started, %{version: version})
    Logger.info("Self-upgrade: starting hot upgrade to #{version}")

    task = Task.Supervisor.async_nolink(@task_supervisor, fn -> Executor.hot_upgrade(version) end)
    timeout_ref = Process.send_after(self(), :upgrade_timeout, state.upgrade_timeout_ms)

    {:started, %{state | task: task, timeout_ref: timeout_ref, upgrading: version}}
  end

  defp finish(result, state) do
    cancel_timer(state.timeout_ref)
    version = state.upgrading
    state = %{state | task: nil, timeout_ref: nil, upgrading: nil}

    case result do
      :ok ->
        emit(:hot_ok, %{version: version})
        %{state | last_failed: nil}

      {:error, reason} ->
        emit(:hot_failed, %{version: version, reason: reason})

        Logger.error(
          "Self-upgrade: hot upgrade to #{version} failed: #{inspect(reason)}. Staying on current version."
        )

        %{state | last_failed: version}
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  # Telemetry and PubSub are observability only. A failure here must never crash
  # the worker or affect the upgrade that already ran.
  defp emit(event, meta) do
    :telemetry.execute([:deployer, :self_upgrade, event], %{count: 1}, meta)
    Phoenix.PubSub.broadcast(Deployer.PubSub, "self_upgrade", {:self_upgrade, event, meta})
  rescue
    error -> Logger.warning("Self-upgrade: emit #{inspect(event)} failed: #{inspect(error)}")
  end
end
